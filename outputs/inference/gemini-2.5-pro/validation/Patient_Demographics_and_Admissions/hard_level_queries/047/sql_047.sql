WITH
  -- Define the ICD-9 and ICD-10 codes for hemorrhagic stroke/intracranial hemorrhage
  hemorrhagic_stroke_codes AS (
    SELECT
      icd_code,
      icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
      -- ICD-9 codes
      (
        icd_version = 9
        AND SUBSTR(icd_code, 1, 3) IN ('430', '431', '432')
      )
      OR
      -- ICD-10 codes
      (
        icd_version = 10
        AND SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62')
      )
  ),
  -- Identify the primary "index" admissions based on the specified criteria
  index_admissions AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    INNER JOIN hemorrhagic_stroke_codes AS hsc
      ON dx.icd_code = hsc.icd_code
      AND dx.icd_version = hsc.icd_version
    WHERE
      pat.gender = 'F'
      AND adm.insurance = 'Medicare'
      AND adm.admission_location = 'EMERGENCY ROOM'
      AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 68 AND 78
      AND dx.seq_num = 1 -- Ensures it's the principal diagnosis
      AND adm.dischtime IS NOT NULL -- Must have a discharge date to calculate readmission
  ),
  -- For the patients identified, find all their admissions and the next admission time
  all_admissions_with_lead AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      LEAD(adm.admittime, 1) OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN (
      SELECT DISTINCT
        subject_id
      FROM index_admissions
    ) AS cohort_patients
      ON adm.subject_id = cohort_patients.subject_id
  ),
  -- Create the final cohort by linking index admissions with readmission data and calculating flags
  final_cohort AS (
    SELECT
      idx.hadm_id,
      DATETIME_DIFF(idx.dischtime, idx.admittime, DAY) AS index_los_days,
      CASE
        WHEN lead_adm.next_admittime IS NOT NULL AND DATETIME_DIFF(lead_adm.next_admittime, idx.dischtime, DAY) <= 30
          THEN 1
        ELSE 0
      END AS is_readmitted_30d
    FROM index_admissions AS idx
    LEFT JOIN all_admissions_with_lead AS lead_adm
      ON idx.hadm_id = lead_adm.hadm_id
  )
-- Aggregate the final cohort data to compute the requested metrics
SELECT
  AVG(is_readmitted_30d) * 100 AS readmission_rate_30d_pct,
  APPROX_QUANTILES(CASE WHEN is_readmitted_30d = 1 THEN index_los_days END, 100)[
  OFFSET
    (50)] AS median_los_readmitted_days,
  APPROX_QUANTILES(CASE WHEN is_readmitted_30d = 0 THEN index_los_days END, 100)[
  OFFSET
    (50)] AS median_los_non_readmitted_days,
  AVG(CASE WHEN index_los_days > 4 THEN 1 ELSE 0 END) * 100 AS pct_with_los_gt_4_days
FROM final_cohort;