WITH cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        -- Approximate age at admission: birth year = anchor_year - anchor_age
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
        p.gender,
        -- Flags for conditions (at least one diagnosis per condition)
        MAX(CASE 
            WHEN d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR 
                 d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%' OR d.icd_code LIKE '250%' 
            THEN 1 ELSE 0 END) AS has_diabetes,
        MAX(CASE 
            WHEN d.icd_code LIKE 'I50%' OR d.icd_code LIKE '428%' 
            THEN 1 ELSE 0 END) AS has_heart_failure
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    WHERE 
        -- Age between 77 and 87 at admission
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 77 AND 87
        AND a.hospital_expire_flag = 0  -- Only discharged patients for window2
    GROUP BY p.subject_id, a.hadm_id, a.admittime, a.dischtime, p.anchor_year, p.anchor_age, p.gender
    HAVING has_diabetes = 1 AND has_heart_failure = 1
),
time_windows AS (
    SELECT 
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        admittime AS window1_start,
        admittime + INTERVAL 48 HOUR AS window1_end,
        dischtime - INTERVAL 72 HOUR AS window2_start,
        dischtime AS window2_end
    FROM cohort
),
prescriptions AS (
    SELECT 
        subject_id,
        hadm_id,
        starttime,
        stoptime,
        drug,
        -- Classify drug
        CASE 
            WHEN drug LIKE '%insulin%' THEN 'insulin'
            WHEN drug IN (
                'metformin', 'glipizide', 'glyburide', 'glimepiride', 'pioglitazone', 
                'rosiglitazone', 'sitagliptin', 'linagliptin', 'alogliptin', 'vildagliptin', 
                'canagliflozin', 'dapagliflozin', 'empagliflozin', 'saxagliptin', 
                'repaglinide', 'nateglinide', 'acarbose', 'miglitol', 'troglitazone'
            ) THEN 'oral'
            ELSE NULL 
        END AS drug_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE drug IS NOT NULL
),
prescription_events AS (
    SELECT 
        t.subject_id,
        t.hadm_id,
        t.window1_start,
        t.window1_end,
        t.window2_start,
        t.window2_end,
        p.drug_class,
        -- For window1
        CASE WHEN p.starttime BETWEEN t.window1_start AND t.window1_end THEN 1 ELSE 0 END AS init_window1,
        CASE WHEN p.stoptime BETWEEN t.window1_start AND t.window1_end THEN 1 ELSE 0 END AS disc_window1,
        -- For window2
        CASE WHEN p.starttime BETWEEN t.window2_start AND t.window2_end THEN 1 ELSE 0 END AS init_window2,
        CASE WHEN p.stoptime BETWEEN t.window2_start AND t.window2_end THEN 1 ELSE 0 END AS disc_window2
    FROM time_windows t
    LEFT JOIN prescriptions p 
        ON t.subject_id = p.subject_id AND t.hadm_id = p.hadm_id
        AND p.drug_class IS NOT NULL  -- Only include classified prescriptions
),
aggregated AS (
    SELECT 
        subject_id,
        hadm_id,
        drug_class,
        -- Window1
        SUM(init_window1) AS initiations_window1,
        SUM(disc_window1) AS discontinuations_window1,
        SUM(init_window1) - SUM(disc_window1) AS net_change_window1,
        -- Window2
        SUM(init_window2) AS initiations_window2,
        SUM(disc_window2) AS discontinuations_window2,
        SUM(init_window2) - SUM(disc_window2) AS net_change_window2
    FROM prescription_events
    GROUP BY subject_id, hadm_id, drug_class
)
SELECT 
    drug_class,
    -- Average net change per patient per drug class per window
    AVG(net_change_window1) AS avg_net_change_window1,
    AVG(net_change_window2) AS avg_net_change_window2
FROM aggregated
GROUP BY drug_class;