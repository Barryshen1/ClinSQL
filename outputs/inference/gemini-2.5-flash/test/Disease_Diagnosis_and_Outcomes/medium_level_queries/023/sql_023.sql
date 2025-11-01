WITH all_admissions_with_diagnoses AS (
    -- Select all relevant admission and patient data with associated ICD-10 diagnoses
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        di.icd_code,
        di.icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F' -- Filter for female patients
        AND di.icd_version = 10 -- Only consider ICD-10 codes for diagnoses
),
aged_filtered_admissions AS (
    -- Calculate age at admission and filter by age range (52-62)
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        EXTRACT(YEAR FROM admittime) - anchor_year + anchor_age AS age_at_admission,
        icd_code
    FROM all_admissions_with_diagnoses
    WHERE
        EXTRACT(YEAR FROM admittime) - anchor_year + anchor_age BETWEEN 52 AND 62
),
stroke_type_flags AS (
    -- Determine if an admission has hemorrhagic or ischemic stroke codes
    SELECT
        hadm_id,
        MAX(CASE WHEN icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' THEN 1 ELSE 0 END) AS is_hemorrhagic_stroke_flag,
        MAX(CASE WHEN icd_code LIKE 'I63%' THEN 1 ELSE 0 END) AS is_ischemic_stroke_flag
    FROM aged_filtered_admissions
    GROUP BY hadm_id
),
main_stroke_cohort AS (
    -- Classify admissions into mutually exclusive ischemic or hemorrhagic stroke groups
    SELECT
        s.hadm_id,
        CASE
            WHEN s.is_hemorrhagic_stroke_flag = 1 AND s.is_ischemic_stroke_flag = 0 THEN 'Hemorrhagic Stroke'
            WHEN s.is_ischemic_stroke_flag = 1 AND s.is_hemorrhagic_stroke_flag = 0 THEN 'Ischemic Stroke'
            ELSE NULL -- Exclude mixed or non-stroke cases from these specific analyses
        END AS stroke_type
    FROM stroke_type_flags s
    WHERE
        (s.is_hemorrhagic_stroke_flag = 1 AND s.is_ischemic_stroke_flag = 0) OR
        (s.is_ischemic_stroke_flag = 1 AND s.is_hemorrhagic_stroke_flag = 0)
),
comorbidity_data AS (
    -- Identify the presence of specific comorbidities and initial flags for CKD and Diabetes
    SELECT
        msc.hadm_id,
        msc.stroke_type,
        afa.subject_id,
        afa.admittime,
        afa.dischtime,
        afa.hospital_expire_flag,
        MAX(CASE WHEN afa.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd, -- Chronic Kidney Disease
        MAX(CASE WHEN afa.icd_code LIKE 'E10%' OR afa.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS has_diabetes, -- Diabetes Mellitus
        -- Other comorbidities for the comorbidity score
        MAX(CASE WHEN afa.icd_code LIKE 'I50%' THEN
            1
        ELSE
            0
        END) AS has_chf, -- Congestive Heart Failure
        MAX(CASE WHEN afa.icd_code LIKE 'J44%' THEN
            1
        ELSE
            0
        END) AS has_copd, -- Chronic Obstructive Pulmonary Disease
        -- CORRECTED: Use LEFT and string comparison for Malignant Neoplasm (C00-C96)
        MAX(CASE WHEN LEFT(afa.icd_code, 3) BETWEEN 'C00' AND 'C96' THEN
            1
        ELSE
            0
        END) AS has_malignancy, -- Malignant Neoplasm (C00-C96)
        MAX(CASE WHEN afa.icd_code LIKE 'K70%' OR afa.icd_code LIKE 'K71%' OR afa.icd_code LIKE 'K72%' OR afa.icd_code LIKE 'K74%' OR afa.icd_code LIKE 'K75%' OR afa.icd_code LIKE 'K76%' THEN
            1
        ELSE
            0
        END) AS has_liver_disease, -- Liver Disease
        MAX(CASE WHEN afa.icd_code LIKE 'I70%' THEN
            1
        ELSE
            0
        END) AS has_pvd, -- Peripheral Vascular Disease
        MAX(CASE WHEN afa.icd_code LIKE 'F00%' OR afa.icd_code LIKE 'F01%' OR afa.icd_code LIKE 'F02%' OR afa.icd_code LIKE 'F03%' THEN
            1
        ELSE
            0
        END) AS has_dementia -- Dementia
    FROM main_stroke_cohort msc
    JOIN aged_filtered_admissions afa
        ON msc.hadm_id = afa.hadm_id
    GROUP BY
        msc.hadm_id, msc.stroke_type, afa.subject_id, afa.admittime, afa.dischtime, afa.hospital_expire_flag
),
comorbidity_tertiles AS (
    -- Calculate comorbidity score and assign tertiles within each stroke type
    SELECT
        hadm_id,
        stroke_type,
        subject_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        has_ckd,
        has_diabetes,
        (has_ckd + has_diabetes + has_chf + has_copd + has_malignancy + has_liver_disease + has_pvd + has_dementia) AS comorbidity_score,
        NTILE(3) OVER (PARTITION BY stroke_type ORDER BY (has_ckd + has_diabetes + has_chf + has_copd + has_malignancy + has_liver_disease + has_pvd + has_dementia)) AS comorbidity_tertile
    FROM comorbidity_data
),
final_cohort_with_los AS (
    -- Calculate Length of Stay (LOS) for each admission
    SELECT
        c.hadm_id,
        c.stroke_type,
        c.hospital_expire_flag,
        DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
        c.has_ckd,
        c.has_diabetes,
        c.comorbidity_score,
        c.comorbidity_tertile
    FROM comorbidity_tertiles c
)
-- Final aggregation to report the required metrics
SELECT
    f.stroke_type,
    f.comorbidity_tertile,
    COUNT(DISTINCT f.hadm_id) AS num_admissions,
    SAFE_DIVIDE(SUM(f.hospital_expire_flag) * 100.0, COUNT(DISTINCT f.hadm_id)) AS in_hospital_mortality_pct,
    APPROX_QUANTILES(f.los_days, 2)[OFFSET(1)] AS median_los_days, -- BigQuery specific for median
    SAFE_DIVIDE(COUNT(CASE WHEN f.los_days < 8 THEN 1 END) * 100.0, COUNT(DISTINCT f.hadm_id)) AS pct_los_lt_8_days,
    SAFE_DIVIDE(COUNT(CASE WHEN f.los_days >= 8 THEN 1 END) * 100.0, COUNT(DISTINCT f.hadm_id)) AS pct_los_ge_8_days,
    SAFE_DIVIDE(SUM(f.has_ckd) * 100.0, COUNT(DISTINCT f.hadm_id)) AS ckd_prevalence_pct,
    SAFE_DIVIDE(SUM(f.has_diabetes) * 100.0, COUNT(DISTINCT f.hadm_id)) AS diabetes_prevalence_pct
FROM final_cohort_with_los f
GROUP BY
    f.stroke_type,
    f.comorbidity_tertile
ORDER BY
    f.stroke_type,
    f.comorbidity_tertile;