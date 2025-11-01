WITH
  icd_uti_codes AS (
    -- Define common ICD codes for Urinary Tract Infection (unspecified site)
    -- N390 for ICD-10, 5990 for ICD-9.
    SELECT 'N390' AS icd_code, 10 AS icd_version
    UNION ALL
    SELECT '5990' AS icd_code, 9 AS icd_version
  ),
  -- Select the base cohort of index admissions matching the specified criteria
  cohort_base AS (
    SELECT
      ad.subject_id,
      ad.hadm_id,
      ad.admittime,
      ad.dischtime,
      -- Calculate Length of Stay in days for the index admission.
      DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
      -- Calculate age at admission
      (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pa
      ON ad.subject_id = pa.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON ad.hadm_id = di.hadm_id
    INNER JOIN icd_uti_codes AS uti
      ON di.icd_code = uti.icd_code AND di.icd_version = uti.icd_version
    WHERE
      pa.gender = 'M' -- Male patients
      AND (pa.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pa.anchor_year)) BETWEEN 60 AND 70 -- Age 60-70 at admission
      AND ad.insurance = 'Medicare' -- Medicare patients
      AND ad.admission_type = 'EMERGENCY' -- Admitted via the Emergency Department
      AND di.seq_num = 1 -- Principal diagnosis (assuming seq_num=1 implies principal diagnosis per MIMIC-IV common practice)
      AND ad.hospital_expire_flag = 0 -- Exclude patients who died during the index admission
  ),
  -- Determine 30-day readmission status for each index admission in the cohort
  readmission_status AS (
    SELECT
      cb.subject_id,
      cb.hadm_id,
      -- Flag as TRUE if any subsequent admission occurs within 30 days of discharge of the index admission
      MAX(
        CASE
          WHEN
            re_adm.hadm_id IS NOT NULL
            AND DATE_DIFF(re_adm.admittime, cb.dischtime, DAY) <= 30
          THEN
            TRUE
          ELSE
            FALSE
        END
      ) AS readmitted_30d_flag
    FROM cohort_base AS cb
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS re_adm
      ON cb.subject_id = re_adm.subject_id
      AND re_adm.hadm_id != cb.hadm_id -- Ensure it's a different admission than the index
      AND re_adm.admittime > cb.dischtime -- Ensure it's a subsequent admission
    GROUP BY
      cb.subject_id,
      cb.hadm_id
  ),
  -- Combine the base cohort data with their respective readmission status
  final_cohort_data AS (
    SELECT
      cb.subject_id,
      cb.hadm_id,
      cb.los_days,
      rs.readmitted_30d_flag
    FROM cohort_base AS cb
    INNER JOIN readmission_status AS rs
      ON cb.subject_id = rs.subject_id AND cb.hadm_id = rs.hadm_id
  )
SELECT
  COUNT(fcd.hadm_id) AS total_index_admissions, -- hadm_id is unique in final_cohort_data, so COUNT() is sufficient
  SUM(CASE WHEN fcd.readmitted_30d_flag THEN 1 ELSE 0 END) AS num_readmitted_30d,
  ROUND(
    (SUM(CASE WHEN fcd.readmitted_30d_flag THEN 1 ELSE 0 END) * 100.0)
    / COUNT(fcd.hadm_id),
    2
  ) AS readmission_rate_30d_percent,
  -- Calculate median LOS specifically for readmitted patients using a scalar subquery
  (
    SELECT
      PERCENTILE_CONT(t.los_days, 0.5) OVER ()
    FROM
      final_cohort_data AS t
    WHERE
      t.readmitted_30d_flag IS TRUE
  ) AS median_los_readmitted_30d,
  -- Calculate median LOS specifically for non-readmitted patients using a scalar subquery
  (
    SELECT
      PERCENTILE_CONT(t.los_days, 0.5) OVER ()
    FROM
      final_cohort_data AS t
    WHERE
      t.readmitted_30d_flag IS FALSE
  ) AS median_los_non_readmitted_30d,
  -- Calculate percentage with LOS > 9 days for readmitted patients
  ROUND(
    (SUM(CASE WHEN fcd.readmitted_30d_flag AND fcd.los_days > 9 THEN 1 ELSE 0 END) * 100.0)
    / NULLIF(SUM(CASE WHEN fcd.readmitted_30d_flag THEN 1 ELSE 0 END), 0),
    2
  ) AS percent_los_gt_9_readmitted,
  -- Calculate percentage with LOS > 9 days for non-readmitted patients
  ROUND(
    (SUM(CASE WHEN NOT fcd.readmitted_30d_flag AND fcd.los_days > 9 THEN 1 ELSE 0 END) * 100.0)
    / NULLIF(SUM(CASE WHEN NOT fcd.readmitted_30d_flag THEN 1 ELSE 0 END), 0),
    2
  ) AS percent_los_gt_9_non_readmitted
FROM
  final_cohort_data AS fcd;