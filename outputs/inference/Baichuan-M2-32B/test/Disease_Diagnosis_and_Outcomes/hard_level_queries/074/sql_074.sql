WITH
  -- Step 1: Compute age at admission for all male patients
  patient_age AS (
    SELECT
      p.subject_id,
      -- Compute birth year: anchor_year - anchor_age
      p.anchor_year - p.anchor_age AS birth_year,
      -- Age at admission: EXTRACT(YEAR FROM admittime) - birth_year
      EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'  -- male
  ),
  -- Step 2: Identify PE admissions (ICD-10 I26) and age 79-89
  pe_admissions AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      p.dod,
      pa.age_at_admission,
      -- For the patient, we might have multiple admissions; we'll take the first one with PE
      ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN
      patient_age pa
      ON a.subject_id = pa.subject_id
    JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    WHERE
      d.icd_code LIKE 'I26%' AND d.icd_version = 10
      AND pa.age_at_admission BETWEEN 79 AND 89
  ),
  -- Step 3: Comorbidity count per admission (distinct ICD-10 diagnoses excluding PE)
  comorbidity_counts AS (
    SELECT
      a.hadm_id,
      COUNT(DISTINCT CASE WHEN d.icd_code NOT LIKE 'I26%' THEN d.icd_code END) AS comorbidity_count
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    WHERE
      d.icd_version = 10
    GROUP BY
      a.hadm_id
  ),
  -- Step 4: Eligible population (all PE admissions with age 79-89 and comorbidity count)
  eligible_population AS (
    SELECT
      pe.subject_id,
      pe.hadm_id,
      pe.admittime,
      pe.dischtime,
      pe.hospital_expire_flag,
      pe.dod,
      pe.age_at_admission,
      c.comorbidity_count
    FROM
      pe_admissions pe
    JOIN
      comorbidity_counts c
      ON pe.hadm_id = c.hadm_id
    WHERE
      pe.rn = 1  -- take the first admission per patient
  ),
  -- Step 5: Compute top quartile threshold (75th percentile) of comorbidity_count in eligible_population
  top_quartile_threshold AS (
    SELECT
      APPROX_QUANTILES(comorbidity_count, 4)[SAFE_OFFSET(3)] AS threshold
    FROM
      eligible_population
  ),
  -- Step 6: Define cohort as eligible_population with comorbidity_count >= threshold
  cohort AS (
    SELECT
      ep.*
    FROM
      eligible_population ep
    WHERE
      ep.comorbidity_count >= (SELECT threshold FROM top_quartile_threshold)
  ),
  -- Step 7: For the patient @subject_id, get their data (even if not in cohort)
  patient_data AS (
    SELECT
      ep.subject_id,
      ep.hadm_id,
      ep.admittime,
      ep.dischtime,
      ep.hospital_expire_flag,
      ep.dod,
      ep.age_at_admission,
      ep.comorbidity_count,
      -- 30-day mortality: if died within 30 days of admission
      CASE
        WHEN ep.dod IS NOT NULL AND DATEDIFF(ep.dod, ep.admittime) <= 30 THEN 1
        ELSE 0
      END AS patient_30day_mortality,
      -- Cardiac complication: any diagnosis in I20-I25 during the admission
      (SELECT MAX(CASE WHEN d.icd_code BETWEEN 'I20' AND 'I25' THEN 1 ELSE 0 END)
       FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
       WHERE d.hadm_id = ep.hadm_id AND d.icd_version = 10) AS patient_cardiac_complication,
      -- Neurologic complication: any diagnosis in G00-G99 during the admission
      (SELECT MAX(CASE WHEN d.icd_code BETWEEN 'G00' AND 'G99' THEN 1 ELSE 0 END)
       FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
       WHERE d.hadm_id = ep.hadm_id AND d.icd_version = 10) AS patient_neuro_complication,
      -- Survival days: if died, then days from admittime to dod; else, to dischtime
      CASE
        WHEN ep.dod IS NOT NULL THEN DATEDIFF(ep.dod, ep.admittime)
        WHEN ep.dischtime IS NOT NULL THEN DATEDIFF(ep.dischtime, ep.admittime)
        ELSE NULL
      END AS patient_survival_days
    FROM
      eligible_population ep
    WHERE
      ep.subject_id = @subject_id
  ),
  -- Step 8: Complications for the cohort (for cohort-level rates)
  cohort_complications AS (
    SELECT
      c.hadm_id,
      MAX(CASE WHEN d.icd_code BETWEEN 'I20' AND 'I25' THEN 1 ELSE 0 END) AS cardiac_complication,
      MAX(CASE WHEN d.icd_code BETWEEN 'G00' AND 'G99' THEN 1 ELSE 0 END) AS neuro_complication
    FROM
      cohort c
    JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.hadm_id = d.hadm_id
    WHERE
      d.icd_version = 10
    GROUP BY
      c.hadm_id
  ),
  -- Step 9: Survival days for the cohort
  cohort_survival AS (
    SELECT
      c.subject_id,
      c.hadm_id,
      CASE
        WHEN c.dod IS NOT NULL THEN DATEDIFF(c.dod, c.admittime)
        WHEN c.dischtime IS NOT NULL THEN DATEDIFF(c.dischtime, c.admittime)
        ELSE NULL
      END AS survival_days
    FROM
      cohort c
  ),
  -- Step 10: Cohort-level metrics
  cohort_metrics AS (
    SELECT
      -- 30-day mortality: proportion of patients who died within 30 days
      AVG(CASE WHEN c.dod IS NOT NULL AND DATEDIFF(c.dod, c.admittime) <= 30 THEN 1.0 ELSE 0 END) AS cohort_30day_mortality,
      -- Cardiac complication rate
      AVG(COALESCE(cc.cardiac_complication, 0)) AS cohort_cardiac_complication_rate,
      -- Neurologic complication rate
      AVG(COALESCE(cc.neuro_complication, 0)) AS cohort_neuro_complication_rate,
      -- Median survival days
      APPROX_QUANTILES(cs.survival_days, 100)[SAFE_OFFSET(50)] AS cohort_median_survival
    FROM
      cohort c
    LEFT JOIN
      cohort_complications cc
      ON c.hadm_id = cc.hadm_id
    LEFT JOIN
      cohort_survival cs
      ON c.hadm_id = cs.hadm_id
  ),
  -- Step 11: For the cohort, compute the percentile rank of comorbidity_count
  cohort_with_rank AS (
    SELECT
      subject_id,
      comorbidity_count,
      PERCENT_RANK() OVER (ORDER BY comorbidity_count) AS percentile
    FROM
      cohort
  ),
  -- Step 12: Get the patient's percentile if they are in the cohort
  patient_percentile AS (
    SELECT
      cr.percentile
    FROM
      cohort_with_rank cr
    WHERE
      cr.subject_id = @subject_id
  )
-- Final output
SELECT
  -- Patient's percentile in the cohort (if in cohort, else NULL)
  (SELECT percentile FROM patient_percentile) AS patient_composite_risk_percentile,
  -- Cohort metrics
  cm.cohort_30day_mortality,
  cm.cohort_cardiac_complication_rate,
  cm.cohort_neuro_complication_rate,
  cm.cohort_median_survival
FROM
  cohort_metrics cm;