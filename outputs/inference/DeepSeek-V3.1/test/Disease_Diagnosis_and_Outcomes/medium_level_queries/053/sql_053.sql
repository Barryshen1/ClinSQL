WITH pneumonia_patients AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        -- Categorize LOS
        CASE 
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
            WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) >= 8 THEN '>=8'
            ELSE 'Other'
        END AS los_group,
        -- Check if ICU on day 1
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
                WHERE icu.hadm_id = a.hadm_id 
                AND icu.intime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
            ) THEN 'ICU on day 1'
            ELSE 'No ICU on day 1'
        END AS day1_icu_status
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 39 AND 49
        AND a.hadm_id IN (
            SELECT hadm_id
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
            WHERE icd_code LIKE 'J69%'   -- Aspiration pneumonia
                OR icd_code LIKE 'J13%'   -- Pneumonia due to S. pneumoniae
                OR icd_code LIKE 'J14%'   -- Pneumonia due to H. influenzae
                OR icd_code LIKE 'J15%'   -- Bacterial pneumonia, not elsewhere classified
                OR icd_code LIKE 'J16%'   -- Pneumonia due to other infectious organisms
                OR icd_code LIKE 'J18%'   -- Pneumonia, organism unspecified
        )
),
comorbidities AS (
    -- Count distinct chronic conditions (excluding pneumonia) per patient
    SELECT 
        hadm_id,
        COUNT(DISTINCT icd_code) AS comorbidity_count
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE hadm_id IN (SELECT hadm_id FROM pneumonia_patients)
        AND icd_code NOT LIKE 'J69%'
        AND icd_code NOT LIKE 'J13%'
        AND icd_code NOT LIKE 'J14%'
        AND icd_code NOT LIKE 'J15%'
        AND icd_code NOT LIKE 'J16%'
        AND icd_code NOT LIKE 'J18%'
    GROUP BY hadm_id
)
SELECT 
    los_group,
    day1_icu_status,
    COUNT(*) AS n_patients,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_percent,
    ROUND(AVG(c.comorbidity_count), 2) AS avg_comorbidity_count
FROM pneumonia_patients pp
LEFT JOIN comorbidities c
    ON pp.hadm_id = c.hadm_id
WHERE los_days >= 1   -- Exclude same-day discharges
GROUP BY los_group, day1_icu_status
ORDER BY los_group, day1_icu_status;