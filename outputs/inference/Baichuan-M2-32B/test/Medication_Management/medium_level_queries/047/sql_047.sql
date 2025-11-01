WITH eligible_patients AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 
        ON a.hadm_id = d1.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd1 
        ON d1.icd_code = dd1.icd_code AND d1.icd_version = dd1.icd_version
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 
        ON a.hadm_id = d2.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2 
        ON d2.icd_code = dd2.icd_code AND d2.icd_version = dd2.icd_version
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 40 AND 50
        AND (dd1.long_title LIKE '%diabetes%' OR dd1.long_title LIKE '%diabetes mellitus%')
        AND (dd2.long_title LIKE '%heart failure%' OR dd2.long_title LIKE '%heart failure with reduced ejection fraction%')
    GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime
),
prescriptions_with_classes AS (
    SELECT 
        p.subject_id,
        p.hadm_id,
        p.starttime,
        p.stoptime,
        p.drug,
        CASE 
            WHEN LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%glipizide%' 
                THEN 'antidiabetic'
            WHEN LOWER(p.drug) LIKE '%metoprolol%' OR LOWER(p.drug) LIKE '%carvedilol%' OR LOWER(p.drug) LIKE '%atenolol%' 
                THEN 'beta-blocker'
            WHEN LOWER(p.drug) LIKE '%lisinopril%' OR LOWER(p.drug) LIKE '%losartan%' OR LOWER(p.drug) LIKE '%valsartan%' 
                THEN 'ACEi/ARB/ARNI'
            WHEN LOWER(p.drug) LIKE '%furosemide%' OR LOWER(p.drug) LIKE '%bumetanide%' OR LOWER(p.drug) LIKE '%torsemide%' 
                THEN 'loop diuretic'
            ELSE NULL
        END AS drug_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN eligible_patients e 
        ON p.subject_id = e.subject_id AND p.hadm_id = e.hadm_id
    WHERE 
        p.starttime <= e.dischtime 
        AND (p.stoptime >= e.admittime OR p.stoptime IS NULL)
),
patient_drug_class_flags AS (
    SELECT 
        e.subject_id,
        e.hadm_id,
        e.admittime,
        e.dischtime,
        d.drug_class,
        MAX(CASE 
            WHEN p.starttime <= e.admittime + INTERVAL 24 HOUR 
                AND p.stoptime >= e.admittime 
                THEN 1 
            ELSE 0 
        END) AS on_first_24h,
        MAX(CASE 
            WHEN p.starttime <= e.dischtime 
                AND p.stoptime >= e.dischtime - INTERVAL 24 HOUR 
                THEN 1 
            ELSE 0 
        END) AS on_last_24h
    FROM eligible_patients e
    LEFT JOIN prescriptions_with_classes p 
        ON e.subject_id = p.subject_id AND e.hadm_id = p.hadm_id
    GROUP BY e.subject_id, e.hadm_id, e.admittime, e.dischtime, d.drug_class
),
prescription_flags AS (
    SELECT 
        p.subject_id,
        p.hadm_id,
        p.drug_class,
        CASE 
            WHEN p.starttime <= e.admittime 
                AND (p.stoptime >= e.dischtime OR p.stoptime IS NULL) 
                THEN 1 
            ELSE 0 
        END AS continued,
        CASE 
            WHEN p.starttime > e.admittime + INTERVAL 24 HOUR 
                THEN 1 
            ELSE 0 
        END AS initiated_late,
        CASE 
            WHEN p.starttime >= e.admittime 
                AND p.stoptime < e.dischtime 
                AND p.stoptime IS NOT NULL 
                THEN 1 
            ELSE 0 
        END AS discontinued
    FROM prescriptions_with_classes p
    INNER JOIN eligible_patients e 
        ON p.subject_id = e.subject_id AND p.hadm_id = e.hadm_id
),
all_drug_classes AS (
    SELECT 'antidiabetic' AS drug_class
    UNION ALL SELECT 'beta-blocker'
    UNION ALL SELECT 'ACEi/ARB/ARNI'
    UNION ALL SELECT 'loop diuretic'
)
SELECT 
    ac.drug_class,
    ROUND(AVG(COALESCE(pdc.on_first_24h, 0)) * 100, 2) AS pct_on_first_24h,
    ROUND(AVG(COALESCE(pdc.on_last_24h, 0)) * 100, 2) AS pct_on_last_24h,
    SUM(COALESCE(pf.continued, 0)) AS count_continued,
    SUM(COALESCE(pf.initiated_late, 0)) AS count_initiated_late,
    SUM(COALESCE(pf.discontinued, 0)) AS count_discontinued
FROM all_drug_classes ac
LEFT JOIN patient_drug_class_flags pdc 
    ON ac.drug_class = pdc.drug_class
LEFT JOIN prescription_flags pf 
    ON ac.drug_class = pf.drug_class
GROUP BY ac.drug_class
ORDER BY ac.drug_class;