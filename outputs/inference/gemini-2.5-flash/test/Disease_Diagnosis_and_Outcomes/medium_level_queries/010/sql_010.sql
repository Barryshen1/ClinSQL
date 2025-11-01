WITH adm AS (
    -- Initial cohort selection: Male patients aged 78-88 with their hospital admissions
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        pa.anchor_age AS age_at_admission,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days -- Calculate Length of Stay in days
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 78 AND 88
),
ami_admissions AS (
    -- Filter for admissions with an Acute Myocardial Infarction (AMI) diagnosis
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        a.age_at_admission,
        a.los_days
    FROM
        adm a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
    WHERE
        (di.icd_version = 9 AND di.icd_code LIKE '410%') -- ICD-9 codes for AMI
        OR (di.icd_version = 10 AND di.icd_code LIKE 'I21%') -- ICD-10 codes for AMI
),
filtered_cohort AS (
    -- Exclude admissions with diagnoses of shock or acute respiratory failure
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        a.age_at_admission,
        a.los_days
    FROM
        ami_admissions a
    WHERE
        NOT EXISTS ( -- Exclude admissions with shock diagnoses
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_shock
            WHERE
                a.subject_id = di_shock.subject_id
                AND a.hadm_id = di_shock.hadm_id
                AND (
                    (di_shock.icd_version = 9 AND di_shock.icd_code LIKE '785.5%') -- ICD-9 codes for Shock (e.g., Cardiogenic shock)
                    OR (di_shock.icd_version = 10 AND di_shock.icd_code LIKE 'R57.%') -- ICD-10 codes for Shock
                )
        )
        AND NOT EXISTS ( -- Exclude admissions with acute respiratory failure diagnoses
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_resp_fail
            WHERE
                a.subject_id = di_resp_fail.subject_id
                AND a.hadm_id = di_resp_fail.hadm_id
                AND (
                    (di_resp_fail.icd_version = 9 AND (di_resp_fail.icd_code LIKE '518.81' OR di_resp_fail.icd_code LIKE '518.83')) -- ICD-9 Acute/Chronic Respiratory Failure (including acute on chronic)
                    OR (di_resp_fail.icd_version = 10 AND (di_resp_fail.icd_code LIKE 'J96.0%' OR di_resp_fail.icd_code LIKE 'J96.2%')) -- ICD-10 Acute/Acute on Chronic Respiratory Failure
                )
        )
),
admissions_with_comorbidities AS (
    -- Identify common comorbidities for each admission in the filtered cohort
    SELECT
        fc.subject_id,
        fc.hadm_id,
        fc.hospital_expire_flag,
        fc.los_days,
        -- Flags for different comorbidity categories (1 if present, 0 if not)
        MAX(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '428.%') OR (di.icd_version = 10 AND di.icd_code LIKE 'I50.%') THEN 1 ELSE 0 END) AS has_chf, -- Congestive Heart Failure
        MAX(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '585.%') OR (di.icd_version = 10 AND di.icd_code LIKE 'N18.%') THEN 1 ELSE 0 END) AS has_ckd_comorbidity, -- Chronic Kidney Disease (specific prevalence)
        MAX(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '250.%') OR (di.icd_version = 10 AND (di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E13%')) THEN 1 ELSE 0 END) AS has_diabetes_comorbidity, -- Diabetes Mellitus (specific prevalence)
        MAX(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '43[0-8]%' OR di.icd_code LIKE '362.3%')) OR (di.icd_version = 10 AND (di.icd_code LIKE 'I6%' OR di.icd_code LIKE 'G45.%' OR di.icd_code LIKE 'H34.0%')) THEN 1 ELSE 0 END) AS has_cvd, -- Cerebrovascular Disease
        MAX(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '44[03]%' OR di.icd_code LIKE '447.1%')) OR (di.icd_version = 10 AND di.icd_code LIKE 'I70.%') THEN 1 ELSE 0 END) AS has_pvd, -- Peripheral Vascular Disease
        MAX(CASE WHEN (di.icd_version = 9 AND (di.icd_code LIKE '491%' OR di.icd_code LIKE '492%' OR di.icd_code LIKE '496')) OR (di.icd_version = 10 AND di.icd_code LIKE 'J44.%') THEN 1 ELSE 0 END) AS has_copd, -- Chronic Obstructive Pulmonary Disease
        MAX(CASE WHEN (di.icd_version = 9 AND (SAFE_CAST(SUBSTR(di.icd_code, 1, 3) AS BIGNUMERIC) BETWEEN 140 AND 208)) OR ( LOWER(di.icd_code) LIKE 'c[0-9][0-9]%' AND LOWER(di.icd_code) NOT LIKE 'c44%') THEN 1 ELSE 0 END) AS has_malignancy, -- Malignancy (excluding skin cancer C44)
        MAX(CASE WHEN (di.icd_version = 9 AND di.icd_code LIKE '571.%') OR (di.icd_version = 10 AND di.icd_code LIKE 'K7[0-6].%') THEN 1 ELSE 0 END) AS has_liver_disease -- Chronic Liver Disease
    FROM
        filtered_cohort fc
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON fc.subject_id = di.subject_id AND fc.hadm_id = di.hadm_id
    GROUP BY
        fc.subject_id,
        fc.hadm_id,
        fc.hospital_expire_flag,
        fc.los_days
),
cohort_with_burden AS (
    -- Calculate comorbidity count and assign burden category; also assign LOS quartiles
    SELECT
        ac.*,
        (
            ac.has_chf + ac.has_ckd_comorbidity + ac.has_diabetes_comorbidity + ac.has_cvd +
            ac.has_pvd + ac.has_copd + ac.has_malignancy + ac.has_liver_disease
        ) AS comorbidity_count,
        CASE -- Assign comorbidity burden
            WHEN (ac.has_chf + ac.has_ckd_comorbidity + ac.has_diabetes_comorbidity + ac.has_cvd +
                  ac.has_pvd + ac.has_copd + ac.has_malignancy + ac.has_liver_disease) <= 1 THEN 'Low'
            WHEN (ac.has_chf + ac.has_ckd_comorbidity + ac.has_diabetes_comorbidity + ac.has_cvd +
                  ac.has_pvd + ac.has_copd + ac.has_malignancy + ac.has_liver_disease) BETWEEN 2 AND 3 THEN 'Medium'
            ELSE 'High'
        END AS comorbidity_burden,
        NTILE(4) OVER (ORDER BY ac.los_days) AS los_quartile_raw -- Calculate LOS quartiles
    FROM
        admissions_with_comorbidities ac
    WHERE ac.los_days >= 0 -- Ensure non-negative LOS
),
final_cohort_grouped AS (
    -- Aggregate data by LOS quartile and comorbidity burden
    SELECT
        -- Refined CASE statement for BigQuery compatibility
        CASE
            WHEN los_quartile_raw = 1 THEN 'Q1'
            WHEN los_quartile_raw = 2 THEN 'Q2'
            WHEN los_quartile_raw = 3 THEN 'Q3'
            WHEN los_quartile_raw = 4 THEN 'Q4'
            ELSE 'Unknown'
        END AS los_quartile,
        comorbidity_burden,
        COUNT(DISTINCT hadm_id) AS total_patients,
        SUM(hospital_expire_flag) AS deaths,
        SUM(CASE WHEN has_ckd_comorbidity THEN 1 ELSE 0 END) AS patients_with_ckd,
        SUM(CASE WHEN has_diabetes_comorbidity THEN 1 ELSE 0 END) AS patients_with_diabetes
    FROM
        cohort_with_burden
    GROUP BY
        los_quartile,
        comorbidity_burden
)
-- Final selection and calculation of mortality rate, prevalence, and 95% Confidence Intervals
SELECT
    los_quartile,
    comorbidity_burden,
    total_patients,
    deaths,
    FORMAT('%.2f%%', SAFE_DIVIDE(deaths, total_patients) * 100.0) AS mortality_rate_percent,
    -- Calculate 95% Confidence Interval for mortality rate using Wilson Score Interval
    -- Formula based on: https://en.wikipedia.org/wiki/Binomial_proportion_confidence_interval#Wilson_score_interval_with_continuity_correction
    -- For simplicity, using the standard Wilson score interval without continuity correction as commonly applied in basic analytics.
    -- p_hat = deaths / total_patients, n = total_patients, z = 1.96 for 95% CI
    FORMAT('%.2f%%',
      (  SAFE_DIVIDE(deaths, total_patients)
        + (1.96 * 1.96) / (2 * total_patients)
        - 1.96 * SQRT(
            SAFE_DIVIDE(deaths, total_patients) * (1 - SAFE_DIVIDE(deaths, total_patients)) / total_patients
            + (1.96 * 1.96) / (4 * total_patients * total_patients)
          )
      ) / (1 + (1.96 * 1.96) / total_patients) * 100.0
    ) AS mortality_ci_lower_percent,
    FORMAT('%.2f%%',
      (  SAFE_DIVIDE(deaths, total_patients)
        + (1.96 * 1.96) / (2 * total_patients)
        + 1.96 * SQRT(
            SAFE_DIVIDE(deaths, total_patients) * (1 - SAFE_DIVIDE(deaths, total_patients)) / total_patients
            + (1.96 * 1.96) / (4 * total_patients * total_patients)
          )
      ) / (1 + (1.96 * 1.96) / total_patients) * 100.0
    ) AS mortality_ci_upper_percent,
    FORMAT('%.2f%%', SAFE_DIVIDE(patients_with_ckd, total_patients) * 100.0) AS ckd_prevalence_percent,
    FORMAT('%.2f%%', SAFE_DIVIDE(patients_with_diabetes, total_patients) * 100.0) AS diabetes_prevalence_percent
FROM
    final_cohort_grouped
WHERE total_patients > 0 -- Exclude groups with no patients for meaningful calculations
ORDER BY
    los_quartile,
    comorbidity_burden;