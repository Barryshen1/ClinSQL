WITH eligible_admissions AS (
    SELECT 
        a.hadm_id, 
        a.subject_id, 
        a.admittime, 
        a.dischtime,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 48 AND 58
        AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
                ON di.icd_code = d.icd_code 
                AND di.icd_version = d.icd_version
            WHERE di.hadm_id = a.hadm_id
                AND d.icd_version = 10
                AND d.icd_code IN (
                    'A40', 'A40.0', 'A40.1', 'A40.2', 'A40.3', 'A40.4', 'A40.5', 'A40.6', 'A40.7', 'A40.8', 'A40.9'
                )
        )
        AND NOT EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
                ON di.icd_code = d.icd_code 
                AND di.icd_version = d.icd_version
            WHERE di.hadm_id = a.hadm_id
                AND d.icd_version = 10
                AND d.icd_code IN ('R57.2', 'R65.21', 'I46.0') -- Example shock codes; may need expansion
        )
),
icu_status AS (
    SELECT 
        ea.*,
        CASE 
            WHEN i.stay_id IS NOT NULL THEN 'ICU'
            ELSE 'No ICU'
        END AS icu_group
    FROM eligible_admissions ea
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON ea.hadm_id = i.hadm_id
),
ultrasound_counts AS (
    SELECT 
        hadm_id, 
        COUNT(*) AS ultrasound_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE icd_code IN (
        '88.71', '88.72', '88.73', '88.74', '88.75', '88.76', '88.77', '88.78', '88.79'
    )
    GROUP BY hadm_id
),
final_data AS (
    SELECT 
        icu_group,
        CASE 
            WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
            WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
        END AS los_bin,
        subject_id,
        COALESCE(uc.ultrasound_count, 0) AS ultrasound_count
    FROM icu_status icu
    LEFT JOIN ultrasound_counts uc 
        ON icu.hadm_id = uc.hadm_id
    WHERE los_bin IS NOT NULL -- Only include the specified LOS bins
)
SELECT 
    icu_group,
    los_bin,
    COUNT(DISTINCT subject_id) AS patient_count,
    AVG(ultrasound_count) AS mean_ultrasounds_per_admission
FROM final_data
GROUP BY icu_group, los_bin
ORDER BY icu_group, los_bin;