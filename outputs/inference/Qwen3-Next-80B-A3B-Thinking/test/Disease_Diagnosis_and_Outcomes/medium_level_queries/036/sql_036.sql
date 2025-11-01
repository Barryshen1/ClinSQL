WITH heart_failure_admissions AS (
    SELECT 
        a.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.hospital_expire_flag,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'F' 
        AND p.anchor_age BETWEEN 39 AND 49
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
                AND ((d.icd_version = 9 AND d.icd_code LIKE '428%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%'))
        )
),

comorbidity_count AS (
    SELECT 
        d.hadm_id,
        COUNT(*) AS comorbidity_count
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN heart_failure_admissions hfa ON d.hadm_id = hfa.hadm_id
    WHERE NOT ((d.icd_version = 9 AND d.icd_code LIKE '428%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%'))
    GROUP BY d.hadm_id
),

comorbidity_tertiles AS (
    SELECT 
        hfa.*,
        cc.comorbidity_count,
        NTILE(3) OVER (ORDER BY cc.comorbidity_count) AS comorbidity_tertile
    FROM heart_failure_admissions hfa
    LEFT JOIN comorbidity_count cc ON hfa.hadm_id = cc.hadm_id
),

diag AS (
    SELECT 
        d.hadm_id,
        MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '585%') OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%') THEN 1 ELSE 0 END) AS has_ckd,
        MAX(CASE WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') OR (d.icd_version = 10 AND d.icd_code LIKE 'E1%') THEN 1 ELSE 0 END) AS has_diabetes
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    GROUP BY d.hadm_id
)

SELECT 
    CASE WHEN los_days <= 5 THEN '≤5' ELSE '>5' END AS los_category,
    CASE 
        WHEN comorbidity_tertile = 1 THEN 'Low'
        WHEN comorbidity_tertile = 2 THEN 'Med'
        WHEN comorbidity_tertile = 3 THEN 'High'
    END AS comorbidity_tertile,
    COUNT(*) AS N,
    AVG(CAST(hospital_expire_flag AS INT64)) * 100 AS mortality_percent,
    AVG(CAST(diag.has_ckd AS INT64)) * 100 AS ckd_prevalence,
    AVG(CAST(diag.has_diabetes AS INT64)) * 100 AS diabetes_prevalence
FROM comorbidity_tertiles
LEFT JOIN diag ON comorbidity_tertiles.hadm_id = diag.hadm_id
GROUP BY los_category, comorbidity_tertile;