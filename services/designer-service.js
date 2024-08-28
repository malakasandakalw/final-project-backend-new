const db = require("../db-connector");

exports.checkUserAvailable = async (id) => {
    try {
        const result = await db.query("SELECT * FROM users WHERE id=$1 AND user_role=(SELECT id FROM user_roles WHERE key='DESIGNER')", [id])
        if (result.rows.length) return true;
        return false;
    } catch (e) {
        console.error('Error when checking DESIGNER aacounts:', e.message, e.stack);
        throw new Error('Error when checking DESIGNER aacounts', e);
    }
}

exports.getAllDesigners = async() => {
    try {
        const result = await db.query("SELECT id, first_name, last_name, email, (SELECT value FROM user_roles WHERE id=users.user_role) as role, profile_picture FROM users WHERE user_role=(SELECT id FROM user_roles WHERE key='DESIGNER') ORDER BY first_name")
        if(result.rows) {
            return result.rows;
        }
    } catch (e) {
        console.error('Error when getting users:', e.message, e.stack);
        throw new Error('Error when getting users', e);
    }
}

exports.getFilteredDesigners = async(userId, followed_only, categories, orderBy, locations, search, pageIndex, pageSize) => {
    try {
        const result = await db.query("SELECT * FROM get_filtered_designers($1,$2,$3,$4,$5,$6,$7,$8)", [userId, followed_only, locations, categories, orderBy, search,pageIndex,pageSize])
        if(result.rows) {

            if (result.rows.length === 0) {
                return { designers: [], total: 0 };
            }
    
            return {
                designers: result.rows,
                total: result.rows[0].total
            };
        }
    } catch (e) {
        console.error('Error when getting users:', e.message, e.stack);
        throw new Error('Error when getting users', e);
    }
}

exports.getDataByDesigner = async(designer_id, user_id) => {
    try {
        const result = await db.query(`SELECT * FROM get_designer_data($1, $2)`, [designer_id, user_id])
        if(result.rows) {
            return result.rows[0]
        }
    } catch (e) {
        console.error('Error when getting users:', e.message, e.stack);
        throw new Error('Error when getting users', e);
    }
}

exports.getPublicFilteredDesigners = async(categories, orderBy, locations, search, pageIndex, pageSize) => {
    try {
        const result = await db.query("SELECT * FROM get_public_designers($1,$2,$3,$4,$5,$6)", [locations, categories, orderBy, search,pageIndex,pageSize])
        if(result.rows) {

            if (result.rows.length === 0) {
                return { designers: [], total: 0 };
            }
    
            return {
                designers: result.rows,
                total: result.rows[0].total
            };

        }
    } catch (e) {
        console.error('Error when getting users:', e.message, e.stack);
        throw new Error('Error when getting users', e);
    }
}

exports.follow = async(designer_id, userId) => {
    try {

        const isRecordAvailable = await db.query("SELECT * FROM followings WHERE user_id=$1 AND designer_id=$2", [userId, designer_id])

        if(isRecordAvailable.rows.length) {
            const result = await db.query("DELETE FROM followings WHERE user_id=$1 AND designer_id=$2", [userId, designer_id])
            if(result) {
                return {followed: false, user_id: userId, designer_id: designer_id}
            }
            return null
        } else {

            const result = await db.query("INSERT INTO followings(user_id, designer_id) VALUES ($1, $2)", [userId, designer_id])
            if (result.rows) {
                return {followed: true, user_id: userId, designer_id: designer_id}
            }
            return null

        }
    } catch (e) {
        console.error('Error when upvoting:', e.message, e.stack);
        throw new Error('Error when upvoting', e)
    }
}
