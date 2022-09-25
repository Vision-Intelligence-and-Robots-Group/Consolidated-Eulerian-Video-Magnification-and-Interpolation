inFile = fullfile('face.mp4');
fprintf('Processing %s\n', inFile);
resultsDir = './result';
amplify_spatial_lpyr_temporal_iir(inFile, resultsDir, 10, 16, 0.4, 0.05,0.1);   % EVM
Mat_amplify_video(inFile, resultsDir, 10, 16, 0.4, 0.05, 0.1, 10)   % MAR: magnification + interpolation
