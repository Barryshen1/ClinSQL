WITH base_admissions AS (
     SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        p.gender,
        -- Compute age at admission: birth_year = p.anchor_year - p.anchor_age
        (YEAR(a.admittime) - (p.anchor_year - p.anchor_age)) AS age_at_admission,
        p.dod
     FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
     INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
     WHERE p.gender = 'F'
        AND (YEAR(a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 88 AND 98
   ),
   ami_admissions AS (
     SELECT DISTINCT hadm_id
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
     WHERE (icd_version = 10 AND icd_code LIKE 'I21%')
        OR (icd_version = 9 AND icd_code LIKE '410%')
   ),
   icu_admissions AS (
     SELECT DISTINCT hadm_id
     FROM `physionet-data.mimiciv_3_1_icu.icustays`
   ),
   mrm_data AS (
     SELECT hadm_id, composite_risk_percentile
     FROM `physionet-data.mimiciv_3_1_hosp.mrm`
   ),
   aki_admissions AS (
     SELECT DISTINCT hadm_id
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
     WHERE (icd_version = 10 AND icd_code IN ('N17.0', 'N17.9'))
        OR (icd_version = 9 AND icd_code IN ('584.5', '584.6', '584.9'))
   ),
   ards_admissions AS (
     SELECT DISTINCT hadm_id
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
     WHERE (icd_version = 10 AND icd_code IN ('J80', 'J98.4'))
        OR (icd_version = 9 AND icd_code IN ('518.81', '518.82', '518.83', '518.84'))
   ),
   cohort AS (
     SELECT 
        b.hadm_id,
        b.subject_id,
        b.age_at_admission,
        m.composite_risk_percentile,
        -- Get the first ICU stay's outtime for this admission
        (SELECT outtime FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
         WHERE i.hadm_id = b.hadm_id 
         ORDER BY intime ASC 
         LIMIT 1) AS first_icu_outtime,
        b.dod,
        CASE WHEN aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS aki_flag,
        CASE WHEN ards.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS ards_flag
     FROM base_admissions b
     INNER JOIN ami_admissions a ON b.hadm_id = a.hadm_id
     INNER JOIN icu_admissions i ON b.hadm_id = i.hadm_id
     INNER JOIN mrm_data m ON b.hadm_id = m.hadm_id
     LEFT JOIN aki_admissions aki ON b.hadm_id = aki.hadm_id
     LEFT JOIN ards_admissions ards ON b.hadm_id = ards.hadm_id
   )
   SELECT
     COUNT(*) AS cohort_size,
     AVG(composite_risk_percentile) AS avg_composite_risk_percentile,
     -- 30-day mortality: count of admissions where death occurred within 30 days after ICU discharge
     COUNT(CASE WHEN first_icu_outtime IS NOT NULL 
                AND dod IS NOT NULL 
                AND dod > first_icu_outtime 
                AND dod <= first_icu_outtime + INTERVAL 30 DAY 
           THEN 1 END) * 1.0 / COUNT(*) AS thirty_day_mortality_rate,
     -- AKI rate
     SUM(aki_flag) * 1.0 / COUNT(*) AS aki_rate,
     -- ARDS rate
     SUM(ards_flag) * 1.0 / COUNT(*) AS ards_rate,
     -- Median survival of decedents (who died after ICU discharge)
     APPROX_QUANTILES(
        CASE WHEN first_icu_outtime IS NOT NULL 
             AND dod IS NOT NULL 
             AND dod > first_icu_outtime 
             THEN DATE_DIFF(CAST(dod AS DATE), CAST(first_icu_outtime AS DATE), DAY) 
        END, 100
     )[OFFSET(50)] AS median_survival_days
   FROM cohort;