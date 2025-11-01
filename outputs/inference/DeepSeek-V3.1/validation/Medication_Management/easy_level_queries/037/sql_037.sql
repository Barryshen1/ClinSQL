WITH ace_prescriptions AS (
    SELECT 
        p.subject_id,
        p.starttime,
        p.stoptime,
        DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON p.subject_id = pt.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.hadm_id = a.hadm_id
    WHERE 
        pt.gender = 'F'
        AND pt.anchor_age = 55
        AND a.hospital_expire_flag = 0  -- Ensure alive at discharge? Not strictly necessary but filters out deaths.
        AND p.stoptime IS NOT NULL
        AND p.starttime IS NOT NULL
        AND DATE_DIFF(p.stoptime, p.starttime, DAY) > 0  -- Positive duration
        AND (
            LOWER(p.drug) LIKE '%enalapril%' OR
            LOWER(p.drug) LIKE '%lisinopril%' OR
            LOWER(p.drug) LIKE '%captopril%' OR
            LOWER(p.drug) LIKE '%ramipril%' OR
            LOWER(p.drug) LIKE '%quinapril%' OR
            LOWER(p.drug) LIKE '%perindopril%' OR
            LOWER(p.drug) LIKE '%trandolapril%' OR
            LOWER(p.drug) LIKE '%fosinopril%' OR
            LOWER(p.drug) LIKE '%benazepril%' OR
            LOWER(p.drug) LIKE '%moexipril%'
        )
)
SELECT 
    APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM ace_prescriptions;