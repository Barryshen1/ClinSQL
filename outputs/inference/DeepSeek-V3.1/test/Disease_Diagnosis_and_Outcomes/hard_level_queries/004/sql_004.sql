WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
        -- Calculate min GCS in first 24h using correct MIMIC-IV item IDs
        MIN(CASE WHEN ce.itemid IN (220739, 223901) AND ce.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR) THEN ce.valuenum END) AS gcs_min,
        -- Check for IVH (presence in diagnoses)
        MAX(CASE WHEN diag_ich.icd_code LIKE '852.0%' OR diag_ich.icd_code LIKE '852.2%' OR diag_ich.icd_code LIKE '852.4%' OR diag_ich.icd_code LIKE 'I61.5%' OR diag_ich.icd_code LIKE 'I61.6%' OR diag_ich.icd_code LIKE 'S06.3%' THEN 1 ELSE 0 END) AS ivh_flag,
        -- Cardiac complication (atrial fibrillation) not present on admission
        MAX(CASE WHEN diag_card.icd_code LIKE '427.3%' OR diag_card.icd_code LIKE 'I48%' THEN 1 ELSE 0 END) AS cardiac_comp,
        -- Neurologic complication (cerebral edema or hydrocephalus) not present on admission
        MAX(CASE WHEN diag_neuro.icd_code LIKE '348.5%' OR diag_neuro.icd_code LIKE 'G93.6%' OR diag_neuro.icd_code LIKE '331.4%' OR diag_neuro.icd_code LIKE 'G91%' THEN 1 ELSE 0 END) AS neuro_comp
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_ich
        ON adm.hadm_id = diag_ich.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON adm.hadm_id = ce.hadm_id AND adm.subject_id = ce.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_card
        ON adm.hadm_id = diag_card.hadm_id AND diag_card.seq_num > 1 
        AND (diag_card.icd_code LIKE '427.3%' OR diag_card.icd_code LIKE 'I48%')
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_neuro
        ON adm.hadm_id = diag_neuro.hadm_id AND diag_neuro.seq_num > 1
        AND (diag_neuro.icd_code LIKE '348.5%' OR diag_neuro.icd_code LIKE 'G93.6%' OR diag_neuro.icd_code LIKE '331.4%' OR diag_neuro.icd_code LIKE 'G91%')
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 44 AND 54
        AND (
            diag_ich.icd_code LIKE 'I60%' OR diag_ich.icd_code LIKE 'I61%' OR diag_ich.icd_code LIKE 'I62%' OR diag_ich.icd_code LIKE 'S06.3%'
            OR diag_ich.icd_code LIKE '430%' OR diag_ich.icd_code LIKE '431%' OR diag_ich.icd_code LIKE '432%' OR diag_ich.icd_code LIKE '852%' OR diag_ich.icd_code LIKE '853%'
        )
    GROUP BY adm.subject_id, adm.hadm_id, adm.hospital_expire_flag, adm.dischtime, adm.admittime
),
risk_score AS (
    SELECT 
        subject_id,
        hadm_id,
        hospital_expire_flag,
        los,
        cardiac_comp,
        neuro_comp,
        CASE 
            WHEN gcs_min BETWEEN 3 AND 8 THEN 2
            WHEN gcs_min BETWEEN 9 AND 12 THEN 1
            WHEN gcs_min BETWEEN 13 AND 15 THEN 0
            ELSE 0
        END AS gcs_points,
        ivh_flag AS ivh_points,
        (CASE 
            WHEN gcs_min BETWEEN 3 AND 8 THEN 2
            WHEN gcs_min BETWEEN 9 AND 12 THEN 1
            WHEN gcs_min BETWEEN 13 AND 15 THEN 0
            ELSE 0
        END) + ivh_flag AS total_risk_score
    FROM cohort
    WHERE gcs_min IS NOT NULL
),
quartiles AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY total_risk_score) AS risk_quartile
    FROM risk_score
),
los_median AS (
    SELECT 
        risk_quartile,
        PERCENTILE_CONT(los, 0.5) AS median_los_survivors
    FROM quartiles
    WHERE hospital_expire_flag = 0
    GROUP BY risk_quartile
)
SELECT 
    q.risk_quartile,
    COUNT(*) AS patient_count,
    ROUND(SUM(q.hospital_expire_flag) / COUNT(*), 3) AS in_hospital_mortality,
    ROUND(SUM(q.cardiac_comp) / COUNT(*), 3) AS cardiac_complication_rate,
    ROUND(SUM(q.neuro_comp) / COUNT(*), 3) AS neurologic_complication_rate,
    lm.median_los_survivors
FROM quartiles q
LEFT JOIN los_median lm
    ON q.risk_quartile = lm.risk_quartile
GROUP BY q.risk_quartile, lm.median_los_survivors
ORDER BY q.risk_quartile;