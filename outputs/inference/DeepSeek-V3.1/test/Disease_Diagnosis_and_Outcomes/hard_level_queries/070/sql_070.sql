WITH cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.deathtime,
        pat.dod,
        pat.gender,
        pat.anchor_age,
        -- Count distinct ICD codes (excluding DVT) as comorbidity proxy
        COUNT(DISTINCT CASE WHEN diag.icd_code NOT LIKE 'I82%' AND diag.icd_code NOT LIKE '453%' THEN diag.icd_code ELSE NULL END) AS comorbidity_count
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE pat.gender = 'F'
        AND pat.anchor_age BETWEEN 59 AND 69
        AND (diag.icd_code LIKE 'I82%' OR diag.icd_code LIKE '453%')  -- DVT codes
    GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.deathtime, pat.dod, pat.gender, pat.anchor_age
),
comorbidity_threshold AS (
    SELECT 
        APPROX_QUANTILES(comorbidity_count, 100)[OFFSET(75)] AS p75
    FROM cohort
),
cohort_filtered AS (
    SELECT 
        cohort.*,
        -- Check if patient died within 30 days of admission
        CASE WHEN dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(admittime), DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30day,
        -- Check if had ICU stay (as proxy for major complication)
        CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu_stay,
        -- Survival days for decedents
        CASE WHEN dod IS NOT NULL THEN DATE_DIFF(DATE(dod), DATE(admittime), DAY) ELSE NULL END AS survival_days
    FROM cohort
    CROSS JOIN comorbidity_threshold
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON cohort.hadm_id = icu.hadm_id
    WHERE cohort.comorbidity_count >= comorbidity_threshold.p75
),
composite_quartiles AS (
    SELECT 
        subject_id,
        hadm_id,
        comorbidity_count,
        NTILE(4) OVER (ORDER BY comorbidity_count) AS risk_quartile
    FROM cohort_filtered
),
decedents_survival AS (
    SELECT 
        PERCENTILE_CONT(survival_days, 0.5) OVER () AS median_survival_days
    FROM cohort_filtered
    WHERE survival_days IS NOT NULL
    LIMIT 1
)
SELECT 
    COUNT(*) AS cohort_size,
    SUM(mortality_30day) AS mortality_30day_count,
    AVG(mortality_30day) * 100 AS mortality_30day_rate,
    SUM(had_icu_stay) AS major_complication_count,
    AVG(had_icu_stay) * 100 AS major_complication_rate,
    (SELECT median_survival_days FROM decedents_survival) AS median_survival_days,
    risk_quartile,
    COUNT(*) AS quartile_count
FROM cohort_filtered
INNER JOIN composite_quartiles
    USING (subject_id, hadm_id)
GROUP BY risk_quartile
ORDER BY risk_quartile;