using HypergeometricFunctions # for the Gauss hypergeometric 2F1 function
using LinearAlgebra 
using Distributions # for generating the multivariate normal
using Plots # for plotting the paths
using DSP # for convolutions 
using DelimitedFiles # for writing the dataset to CSV
using StatsBase
using SpecialFunctions
using Random

# Essentially uses the same functions and algorithm as the BSS process simulation
# Difference in the kernel which includes a rotational part
# splits into real and imaginary coordinates 
# slightly slower than the complex version

function hybridSchemeCovarianceMatrix(kappa, n, alpha)
# Covariance matrix used in the hybrid scheme simulations
    # create empty matrix
    Sigma = zeros(kappa + 1, kappa + 1)
    # fill in top corner = Var(W_i)
    Sigma[1,1] = 1/n
    # loop over other columns
    for j = 2:(kappa + 1)
        # fill in according to given expressions
        Sigma[1,j] = ((j-1)^(alpha+1) - (j-2)^(alpha+1))/(alpha+1)/n^(alpha+1)

        Sigma[j,j] = ((j-1)^(2*alpha+1) - (j-2)^(2*alpha+1))/(2*alpha+1)/n^(2*alpha+1)
        # fill in remaining rows
        if j < kappa + 1 
            for k = (j+1):(kappa+1)
              Sigma[j,k] = 1/(alpha + 1)/n^(2*alpha + 1) * ((j - 1)^(alpha + 1) * (k - 1)^alpha * _₂F₁(-alpha, 1, alpha + 2, (j - 1)/(k - 1) ) - (j - 2)^(alpha + 1) * (k - 2)^alpha * _₂F₁(-alpha, 1, alpha + 2, (j - 2)/(k - 2) ))
            end
        end

    end
    # fill in lower triangle so that S[i,j] = S[j,i]
    # return matrix
    return Matrix(Symmetric(Sigma))

end


# kernal function split into x and y components
# kernel is unnormalised
# includes a rotational aspect of constant rate omega * t

g_x(t, alpha, lambda, omega) = t^alpha * exp(-lambda*t) * cos( omega * t)

g_y(t, alpha, lambda, omega) = t^alpha * exp(-lambda*t) * sin( omega * t)



b_star(k, alpha) =  ((k^(alpha + 1) - (k-1)^(alpha + 1))/(alpha + 1))^(1/alpha)
# optimal discretisation b* value function 


function maternProcess(N::Int, n::Int, T::Int, kappa::Int, alpha, lambda, omega) 
# simulating from a Matern process using the hybrid Scheme
# X and Y are now the two dimensions of the process

    # create empty vectors for the 'lower' part of the hybrid scheme sums
    X_lower = zeros(n*T + 1)
    Y_lower = zeros(n*T + 1)
    
    # split indices into lower and upper sums
    k_lower = 1:kappa
    k_upper = (kappa + 1):N

    # vector of the L_g(k/n)
    L_g_x = exp.(-lambda.*k_lower/n) .* cos.(omega .* k_lower/n)
    L_g_y = exp.(-lambda.*k_lower/n) .* sin.(omega .* k_lower/n)

    # vector of g(b*/n) for hybrid scheme
    g_b_star_x = [zeros(kappa); g_x.(b_star.(k_upper, alpha)/n, alpha, lambda, omega)]
    g_b_star_y = [zeros(kappa); g_y.(b_star.(k_upper, alpha)/n, alpha, lambda, omega)]
    ## generate the volatility process
   
    # create the required covariance matrix
    Sigma_W = hybridSchemeCovarianceMatrix(kappa, n, alpha)

    # generate the multivariate distribution
    d = MvNormal(Sigma_W)

    # sample N + n*T random variables from this multivariate Gaussian
    # same Brownian increments need to be used for both X and Y directions
    W = transpose(rand(d, N + n*T))

    ## create the sample hybrid scheme and Riemann sum sample paths
    # split into cases as when kappa = 1, we are dealing with a scalar not a matrix in the first sum
    if kappa == 1 
        # loop over each time i/n with i = 0, ..., n*T
        for i = 1:(n*T + 1) 
        # calculate X[i] = X(i-1/n) from hybrid scheme
        # sum first kappa terms and remaining N - kappa terms separately
            
            # generate the lower sums for the two directions
            X_lower[i] <- sum( L_g_x  * W[(i + N - kappa):(i+N-1), 2])
            Y_lower[i] = sum( L_g_y  .* W[(i + N - kappa):(i+N-1), 2])
        end

    else # if kappa > 1
        # loop over each time i/n with i = 0, ..., n*T
        for i = 1:(n*T + 1)
        # sum first kappa terms and remaining N - kappa terms separately
        
        # generate the lower sums for the two directions
        X_lower[i] = sum( L_g_x  .* diag(reverse(W[(i + N - kappa):(i+N-1), 2:(kappa + 1)], dims = 1)))        
        Y_lower[i] = sum( L_g_y  .* diag(reverse(W[(i + N - kappa):(i+N-1), 2:(kappa + 1)], dims = 1)))
        
        end
        
        # convolve with the Brownian increments in each dimension
        X = X_lower + conv( g_b_star_x, (W[:,1]))[N:(N+n*T)]
        Y = Y_lower + conv( g_b_star_y, (W[:,1]))[N:(N+n*T)] 
    end

    # return the sample path as (X,Y) coordinate vectors
    return X, Y

end



### to produce an entire simulated dataset: 

# set parameter values

num_simulations = 10
n = 25000
N = 150000
T = 1
kappa = 5
alpha = -0.2
lambda = 100
omega = 8

Random.seed!(3)
mp = maternProcess(N, n, T, kappa, alpha, lambda, omega)
plot(mp[1], mp[2])


plot(cumsum(mp[1]), cumsum(mp[2]))

writedlm("x_coord.csv", cumsum(mp[1]), ",")
writedlm("y_coord.csv", cumsum(mp[2]), ",")




# create matrices to store the datasets

all_X = zeros(num_simulations, n*T + 1)
all_Y = zeros(num_simulations, n*T + 1)

# simulate data

for i = 1:num_simulations
    simulation = maternProcess(N, n, T, kappa, alpha, lambda, omega)
    println(i)
end

# write the data to csv files

writedlm("all_X.csv", all_X, ",")
writedlm("all_Y.csv", all_Y, ",")

# to test the simulations, compare the empirical acf to the true one

# function that returns the exact Matern autocorrelation function

function maternAutocorrelation(alpha, lambda, n, h)
    if h == 0
        return 1
    else
        return 2/gamma(alpha + 1/2) / 2^(alpha + 1/2) * (lambda * h / n)^(alpha + 1/2) * besselk(alpha + 1/2, lambda * h / n)
    end
    
end

# function that returns the sample autocorrelation of a zero mean, complex valued time series
sampleAutocorrelation(Z, h) = dot(Z[1:end-h], Z[h + 1:end]) / dot(Z,Z)
    
    
# generate some plots to compare the autocorrelation functions

all_h = 0:5000
all_rho = maternAutocorrelation.(alpha, lambda, n, all_h)
all_rho_hat = Array{ComplexF64}(undef, 5001)
mp = maternProcess(N, n, T, kappa, alpha, lambda, omega)

for h = 0:5000
    all_rho_hat[h+1] = sampleAutocorrelation(mp[1]+mp[2]im, h)
end

plot(0:5000,[all_rho, real(all_rho_hat)])

# looks good!







