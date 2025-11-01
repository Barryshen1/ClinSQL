WITH cohort AS (
    SELECT 
        a.hadm_id, 
        a.admittime, 
        a.deathtime, 
        a.hospital_expire_flag,
        p.gender, 
        p.anchor_age,
        EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
            ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
        WHERE d.hadm_id = a.hadm_id 
          AND LOWER(di.long_title) LIKE '%pneumonia%'
    )
    AND p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 88 AND 98
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.hadm_id = a.hadm_id
    )
),
icu_stays AS (
    SELECT 
        i.hadm_id, 
        i.stay_id, 
        i.intime,
        ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),
sofa_scores AS (
    SELECT 
        i.stay_id, 
        c.valuenum AS sofa_score
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN icu_stays i ON c.stay_id = i.stay_id
    WHERE c.itemid = 223900
      AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL '24' HOUR
),
aki_diagnosis AS (
    SELECT 
        d.hadm_id, 
        1 AS has_aki
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE LOWER(di.long_title) LIKE '%acute kidney injury%' 
       OR d.icd_code LIKE 'N17%'
),
ards_diagnosis AS (
    SELECT 
        d.hadm_id, 
        1 AS has_ards
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE LOWER(di.long_title) LIKE '%acute respiratory distress syndrome%' 
       OR d.icd_code = 'J80'
)
SELECT 
    COUNT(DISTINCT c.hadm_id) AS cohort_size,
    MIN(s.sofa_score) AS min_sofa,
    PERCENTILE_CONT(s.sofa_score, 0.25) WITHIN GROUP (ORDER BY s.sofa_score) AS q25_sofa,
    PERCENTILE_CONT(s.sofa_score, 0.5) WITHIN GROUP (ORDER BY s.sofa_score) AS median_sofa,
    PERCENTILE_CONT(s.sofa_score, 0.75) WITHIN GROUP (ORDER BY s.sofa_score) AS q75_sofa,
    MAX(s.sofa_score) AS max_sofa,
    AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate,
    CAST(COUNTIF(a.has_aki = 1) AS FLOAT64) / COUNT(*) AS aki_rate,
    CAST(COUNTIF(ar.has_ards = 1) AS FLOAT64) / COUNT(*) AS ards_rate,
    PERCENTILE_CONT(CASE WHEN c.hospital_expire_flag = 1 THEN DATE_DIFF(c.deathtime, c.admittime, DAY) END, 0.5) WITHIN GROUP (ORDER BY CASE WHEN c.hospital_expire_flag = 1 THEN DATE_DIFF(c.deathtime, c.admittime, DAY) END) AS median_survival_days_decedents
FROM cohort c
LEFT JOIN icu_stays i ON c.hadm_id = i.hadm_id AND i.rn = 1
LEFT JOIN sofa_scores s ON i.stay_id = s.stay_id
LEFT JOIN aki_diagnosis a ON c.hadm_id = a.hadm_id
LEFT JOIN ards_diagnosis ar ON c.hadm_id = ar.hadm_id;