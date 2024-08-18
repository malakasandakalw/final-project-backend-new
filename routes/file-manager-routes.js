const fs = require('fs');
const express = require('express');
const TokenAuthenticator = require('../middlewares/TokenAuthenticator');
const router = express.Router();
const path = require('path');

router.post("/upload", (req, res) => {
    const files = req.body.files
    const filesUploaded = []

    files.forEach(file => {
        const base64Data = file.data.replace(/^data:.*;base64,/, '');
        const fileName = Date.now() + '-' + file.name;
        const filePath = path.join(__dirname, '../uploads/', fileName);
        fs.writeFileSync(filePath, base64Data, 'base64');
        let fileType = 'image';
        if(isImageFile(fileName)) {
            fileType = 'image'
        } else if(isVideoFile(fileName)) {
            fileType = 'video'
        }
        filesUploaded.push({
            name: file.name,
            type: fileType,
            url: `/uploads/${fileName}`
        });
    });

    return res.status(200).json({ message: 'Uploaded Successfully', body: {files: filesUploaded}, status: 'success' });

})

function isImageFile(fileName) {
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'tiff'];
    const fileExtension = fileName.split('.').pop().toLowerCase();
    return imageExtensions.includes(fileExtension);
}

function isVideoFile(fileName) {
    const videoExtensions = ['mp4', 'mkv', 'webm', 'avi', 'mov', 'wmv', 'flv', '3gp'];
    const fileExtension = fileName.split('.').pop().toLowerCase();
    return videoExtensions.includes(fileExtension);
}

module.exports = router;