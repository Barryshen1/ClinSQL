WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        -- Categorize LOS
        CASE 
            WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
            WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
            ELSE 'Other'
        END AS los_category,
        -- Check if ICU stay occurred
        CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS icu_status
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    -- Filter for lower GI bleed diagnoses (ICD-9: 578.9, 578.1, 569.3; ICD-10: K92.2, K62.5, K55.21)
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
        AND (
            (d.icd_version = 9 AND d.icd_code IN ('5789', '5781', '5693')) OR
            (d.icd_version = 10 AND d.icd_code IN ('K922', 'K625', 'K5521'))
        )
    -- Left join to icustays to determine ICU status
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 62 AND 72
        AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
procedures AS (
    SELECT 
        h.hadm_id,
        h.hcpcs_cd,
        h.chartdate
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    WHERE 
        -- Non-invasive diagnostics: Imaging, ECG, EEG, PFT
        -- Example HCPCS codes:
        -- Imaging: 71045 (Chest X-ray), 74150 (CT Abdomen), 70450 (CT Head), 76705 (US Abdomen)
        -- ECG: 93005 (ECG), 93010 (ECG rhythm)
        -- EEG: 95812 (EEG), 95813 (EEG sleep)
        -- PFT: 94010 (Spirometry), 94060 (PFT)
        h.hcpcs_cd IN (
            '71045', '74150', '70450', '76705',
            '93005', '93010',
            '95812', '95813',
            '94010', '94060'
        )
),
count_procedures AS (
    SELECT 
        c.hadm_id,
        c.los_category,
        c.icu_status,
        COUNT(DISTINCT p.hcpcs_cd) AS num_procedures
    FROM cohort c
    LEFT JOIN procedures p
        ON c.hadm_id = p.hadm_id
    GROUP BY c.hadm_id, c.los_category, c.icu_status
)
SELECT 
    los_category,
    icu_status,
    AVG(num_procedures) AS mean_procedures_per_admission,
    COUNT(*) AS num_admissions
FROM count_procedures
GROUP BY los_category, icu_status
ORDER BY los_category, icu_status;