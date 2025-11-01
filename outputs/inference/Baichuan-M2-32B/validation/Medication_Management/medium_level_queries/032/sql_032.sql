WITH
  eligible_admissions AS (
    SELECT
      a.hadm_id,
      a.subject_id,
      a.admittime,
      a.dischtime,
      p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 51 AND 61
  ),
  diabetes_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code BETWEEN 'E10' AND 'E14'
      AND icd_version = 10
  ),
  heart_failure_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE 'I50%'
      AND icd_version = 10
  ),
  cohort_admissions AS (
    SELECT
      e.hadm_id,
      e.admittime,
      e.dischtime,
      TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR) AS first_24h_end_raw,
      TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR) AS final_12h_start_raw
    FROM eligible_admissions e
    WHERE e.hadm_id IN (SELECT hadm_id FROM diabetes_admissions)
      AND e.hadm_id IN (SELECT hadm_id FROM heart_failure_admissions)
  ),
  insulin_orders AS (
    SELECT
      p.hadm_id,
      p.starttime,
      p.stoptime,
      p.drug,
      CASE
        WHEN p.drug LIKE '%glargine%' OR p.drug LIKE '%detemir%' 
             OR p.drug LIKE '%degludec%' OR p.drug LIKE '%NPH%' 
             OR p.drug LIKE '%zinc%' THEN 'basal'
        WHEN p.drug LIKE '%aspart%' OR p.drug LIKE '%lispro%' 
             OR p.drug LIKE '%glulisine%' OR p.drug LIKE '%regular%' THEN 'bolus'
        ELSE NULL
      END AS insulin_type,
      CASE WHEN po.order_subtype LIKE '%sliding scale%' THEN 1 ELSE 0 END AS is_sliding_scale
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.poe` po
      ON p.poe_id = po.poe_id
    WHERE p.drug LIKE '%insulin%'
  ),
  admission_periods AS (
    SELECT
      c.hadm_id,
      c.admittime AS first_24h_start,
      CASE
        WHEN c.first_24h_end_raw > c.dischtime THEN c.dischtime
        ELSE c.first_24h_end_raw
      END AS first_24h_end,
      CASE
        WHEN c.final_12h_start_raw < c.admittime THEN c.admittime
        ELSE c.final_12h_start_raw
      END AS final_12h_start,
      c.dischtime AS final_12h_end
    FROM cohort_admissions c
  ),
  period_regimens AS (
    SELECT
      ap.hadm_id,
      'first_24h' AS period,
      MAX(CASE WHEN io.insulin_type = 'basal' 
               AND io.starttime <= ap.first_24h_end 
               AND (io.stoptime >= ap.first_24h_start OR io.stoptime IS NULL) 
              THEN 1 ELSE 0 END) AS has_basal,
      MAX(CASE WHEN io.insulin_type = 'bolus' 
               AND io.starttime <= ap.first_24h_end 
               AND (io.stoptime >= ap.first_24h_start OR io.stoptime IS NULL) 
              THEN 1 ELSE 0 END) AS has_bolus,
      MAX(CASE WHEN io.is_sliding_scale = 1 
               AND io.starttime <= ap.first_24h_end 
               AND (io.stoptime >= ap.first_24h_start OR io.stoptime IS NULL) 
              THEN 1 ELSE 0 END) AS has_sliding_scale
    FROM admission_periods ap
    LEFT JOIN insulin_orders io
      ON ap.hadm_id = io.hadm_id
    GROUP BY ap.hadm_id, period

    UNION ALL

    SELECT
      ap.hadm_id,
      'final_12h' AS period,
      MAX(CASE WHEN io.insulin_type = 'basal' 
               AND io.starttime <= ap.final_12h_end 
               AND (io.stoptime >= ap.final_12h_start OR io.stoptime IS NULL) 
              THEN 1 ELSE 0 END) AS has_basal,
      MAX(CASE WHEN io.insulin_type = 'bolus' 
               AND io.starttime <= ap.final_12h_end 
               AND (io.stoptime >= ap.final_12h_start OR io.stoptime IS NULL) 
              THEN 1 ELSE 0 END) AS has_bolus,
      MAX(CASE WHEN io.is_sliding_scale = 1 
               AND io.starttime <= ap.final_12h_end 
               AND (io.stoptime >= ap.final_12h_start OR io.stoptime IS NULL) 
              THEN 1 ELSE 0 END) AS has_sliding_scale
    FROM admission_periods ap
    LEFT JOIN insulin_orders io
      ON ap.hadm_id = io.hadm_id
    GROUP BY ap.hadm_id, period
  ),
  regimen_flags AS (
    SELECT
      hadm_id,
      period,
      has_basal,
      has_bolus,
      has_sliding_scale,
      (has_basal * has_bolus) AS has_basal_bolus  -- Fixed: INT64 instead of BOOL
    FROM period_regimens
  ),
  unpivoted_regimens AS (
    SELECT
      hadm_id,
      period,
      'Basal-Bolus' AS regimen,
      has_basal_bolus AS has_regimen
    FROM regimen_flags
    UNION ALL
    SELECT
      hadm_id,
      period,
      'Basal',
      has_basal
    FROM regimen_flags
    UNION ALL
    SELECT
      hadm_id,
      period,
      'Bolus',
      has_bolus
    FROM regimen_flags
    UNION ALL
    SELECT
      hadm_id,
      period,
      'sliding-scale',
      has_sliding_scale
    FROM regimen_flags
  ),
  regimen_prevalence AS (
    SELECT
      period,
      regimen,
      COUNT(CASE WHEN has_regimen = 1 THEN 1 END) * 100.0 / COUNT(*) AS prevalence_percent
    FROM unpivoted_regimens
    GROUP BY period, regimen
  ),
  pivoted_prevalence AS (
    SELECT
      regimen,
      MAX(CASE WHEN period = 'first_24h' THEN prevalence_percent END) AS first_24h_prevalence,
      MAX(CASE WHEN period = 'final_12h' THEN prevalence_percent END) AS final_12h_prevalence
    FROM regimen_prevalence
    GROUP BY regimen
  )
SELECT
  regimen,
  first_24h_prevalence,
  final_12h_prevalence,
  (final_12h_prevalence - first_24h_prevalence) AS pct_point_change
FROM pivoted_prevalence
ORDER BY regimen;