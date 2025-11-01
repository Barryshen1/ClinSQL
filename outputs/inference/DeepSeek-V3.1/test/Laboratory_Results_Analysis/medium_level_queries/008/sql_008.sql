WITH acs_patients AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 87 AND 97
        AND a.hadm_id IN (
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE 
                (icd_version = 10 AND icd_code LIKE 'I21%') OR  -- MI codes
                (icd_version = 10 AND icd_code = 'I20.0') OR    -- Unstable angina
                (icd_version = 9 AND icd_code LIKE '410%') OR   -- MI codes (ICD-9)
                (icd_version = 9 AND icd_code = '411.1')        -- Unstable angina (ICD-9)
        )
),
first_troponin AS (
    SELECT 
        l.hadm_id,
        l.valuenum AS troponin_value,
        l.charttime,
        ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
        ON l.itemid = d.itemid
    WHERE d.label LIKE '%Troponin T%'
        AND l.valuenum IS NOT NULL
)
SELECT 
    CASE 
        WHEN ft.troponin_value <= 0.01 THEN 'Normal/Minimal'
        WHEN ft.troponin_value > 0.01 AND ft.troponin_value <= 0.1 THEN 'Borderline'
        WHEN ft.troponin_value > 0.1 THEN 'Elevated'
    END AS troponin_category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
    ROUND(SUM(ap.hospital_expire_flag) * 100.0 / COUNT(*), 2) AS in_hospital_mortality_rate
FROM acs_patients ap
INNER JOIN first_troponin ft
    ON ap.hadm_id = ft.hadm_id
WHERE ft.rn = 1  -- first Troponin measurement
GROUP BY troponin_category
ORDER BY 
    CASE 
        WHEN troponin_category = 'Normal/Minimal' THEN 1
        WHEN troponin_category = 'Borderline' THEN 2
        WHEN troponin_category = 'Elevated' THEN 3
    END;