% amplify_spatial_lpyr_temporal_iir(vidFile, resultsDir, ...
%                                   alpha, lambda_c, r1, r2, chromAttenuation)
% 
% Spatial Filtering: Laplacian pyramid
% Temporal Filtering: substraction of two IIR lowpass filters
% 
% y1[n] = r1*x[n] + (1-r1)*y1[n-1]
% y2[n] = r2*x[n] + (1-r2)*y2[n-1]
% (r1 > r2)
%
% y[n] = y1[n] - y2[n]
%
% Copyright (c) 2011-2012 Massachusetts Institute of Technology, 
% Quanta Research Cambridge, Inc.
%
% Authors: Hao-yu Wu, Michael Rubinstein, Eugene Shih, 
% License: Please refer to the LICENCE file
% Date: June 2012
%

%inFile = fullfile(dataDir,'baby.mp4');
%fprintf('Processing %s\n', inFile);
%amplify_spatial_lpyr_temporal_iir(inFile, resultsDir, 10, 16, 0.4, 0.05, 0.1);

function amplify_spatial_lpyr_temporal_iir(vidFile, resultsDir, ...
            alpha, lambda_c, r1, r2, chromAttenuation)
 
    [~,vidName] = fileparts(vidFile);   %vidName:face
    outName = fullfile(resultsDir,[vidName 'EVM_result-iir-r1-' num2str(r1)...
        '-r2-' num2str(r2)...
        '-alpha-' num2str(alpha) ...
        '-lambda_c-' num2str(lambda_c) ...
        '-chromAtn-' num2str(chromAttenuation) '.avi']);

    % Read video
    vid = VideoReader(vidFile);
    % Extract video info
    vidHeight = vid.Height; 
    vidWidth = vid.Width;  
    nChannels = 3;
    fr = vid.FrameRate; 
    len = vid.NumberOfFrames;  
    temp = struct('cdata', ...
		  zeros(vidHeight, vidWidth, nChannels, 'uint8'), ...
		  'colormap', []); 


    startIndex = 1;
    endIndex = len-10;  

    vidOut = VideoWriter(outName);
    vidOut.FrameRate = fr;

    open(vidOut)

    % get the first frame and transfer to type ntsc
    temp.cdata = read(vid, startIndex);
    [rgbframe,~] = frame2im(temp);  
    rgbframe = im2double(rgbframe);
    frame = rgb2ntsc(rgbframe);
    
    % get the 3-channel Laplace pyramid of the first frame
    % The second through the eighth layers of the Laplace pyramid are Gaussian pyramids subtracting the upsampled image from the same layer, but the first layer of the Laplace pyramid is Gaussian pyramid, and the first layer does not subsample, and no subtraction is performed.
    % pyr: The column vector that stores the values of the Laplace pyramid
    % The first element of pyr is the first element of the last layer of pyramid, 
    % the last element of pyris the last element of the top layer of pyramid.
    % pid: The dimensions of the layers of Laplace pyramid (8 layers)
    [pyr,pind] = buildLpyr(frame(:,:,1),'auto');   
    pyr = repmat(pyr,[1 3]);    
    [pyr(:,2),~] = buildLpyr(frame(:,:,2),'auto');
    [pyr(:,3),~] = buildLpyr(frame(:,:,3),'auto');  
    
    lowpass1 = pyr;
    lowpass2 = pyr;

    output = rgbframe;
    %im2uint8: normalization and transfer to type uint8
    writeVideo(vidOut,im2uint8(output));

    nLevels = size(pind,1); %nLevels=8

    for i=startIndex+1:endIndex
            % get the frames and transfer to type ntsc
            progmeter(i-startIndex,endIndex - startIndex + 1);
            temp.cdata = read(vid, i);
            [rgbframe,~] = frame2im(temp);

            rgbframe = im2double(rgbframe);
            frame = rgb2ntsc(rgbframe);
            
            % Construct 3-channel Laplacian pyramid
            [pyr(:,1),~] = buildLpyr(frame(:,:,1),'auto');
            [pyr(:,2),~] = buildLpyr(frame(:,:,2),'auto');
            [pyr(:,3),~] = buildLpyr(frame(:,:,3),'auto');
            
            % temporal filtering
            lowpass1 = (1-r1)*lowpass1 + r1*pyr;
            lowpass2 = (1-r2)*lowpass2 + r2*pyr;

            filtered = (lowpass1 - lowpass2);
            
            
            %% amplify each spatial frequency bands according to Figure 6 of our paper
            ind = size(pyr,1);

            delta = lambda_c/8/(1+alpha);
            
            % the factor to boost alpha above the bound we have in the
            % paper. (for better visualization)
            exaggeration_factor = 2;

            % compute the representative wavelength lambda for the lowest spatial 
            % freqency band of Laplacian pyramid
            lambda = (vidHeight^2 + vidWidth^2).^0.5/3; % 3 is experimental constant
            % Be careful not to confuse l with 1
            for l = nLevels:-1:1
              indices = ind-prod(pind(l,:))+1:ind;
              % compute modified alpha for this level
              currAlpha = lambda/delta/8 - 1;
              currAlpha = currAlpha*exaggeration_factor;
              
              if (l == nLevels || l == 1) % ignore the highest and lowest frequency band
                  filtered(indices,:) = 0;
              elseif (currAlpha > alpha)  % representative lambda exceeds lambda_c
                  filtered(indices,:) = alpha*filtered(indices,:);
              else
                  filtered(indices,:) = currAlpha*filtered(indices,:);
              end

              ind = ind - prod(pind(l,:));
              % go one level down on pyramid, 
              % representative lambda will reduce by factor of 2
              lambda = lambda/2; 
            end
            
            
            %% Render on the input video
            output = zeros(size(frame));
            
            output(:,:,1) = reconLpyr(filtered(:,1),pind);
            output(:,:,2) = reconLpyr(filtered(:,2),pind);
            output(:,:,3) = reconLpyr(filtered(:,3),pind);
            % Suppressing the color channel, relatively amplifies the brightness channel
            output(:,:,2) = output(:,:,2)*chromAttenuation; 
            output(:,:,3) = output(:,:,3)*chromAttenuation;
            % add the amplified vedio to the original one
            output = frame + output;
            % transfer type ntsc to rgb
            output = ntsc2rgb(output); 
%             filtered = rgbframe + filtered.*mask;
            % Correction for the values beyond normalization
            output(output > 1) = 1;
            output(output < 0) = 0;
            % Writes a frame to a video. The first parameter is the video object, and the second parameter is the frames of the video
            writeVideo(vidOut,im2uint8(output));    
            
            
                      
    end
    close(vidOut);
end
