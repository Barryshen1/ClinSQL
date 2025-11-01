WITH
  eligible_patients AS (
    SELECT
      p.subject_id,
      p.anchor_age,
      p.gender
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 39 AND 49
  ),
  admissions_with_diagnoses AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    WHERE
      TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
  ),
  admissions_with_conditions AS (
    SELECT
      ad.subject_id,
      ad.hadm_id,
      ad.admittime,
      ad.dischtime,
      ad.los_hours
    FROM
      admissions_with_diagnoses ad
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      ON ad.hadm_id = d1.hadm_id
      AND d1.icd_code LIKE 'E11%'
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      ON ad.hadm_id = d2.hadm_id
      AND d2.icd_code LIKE 'I50%'
    GROUP BY
      ad.subject_id, ad.hadm_id, ad.admittime, ad.dischtime, ad.los_hours
  ),
  cohort AS (
    SELECT
      ep.subject_id,
      awc.hadm_id,
      awc.admittime,
      awc.dischtime,
      awc.los_hours
    FROM
      eligible_patients ep
    INNER JOIN
      admissions_with_conditions awc
      ON ep.subject_id = awc.subject_id
  ),
  admission_periods AS (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) AS first_72h_end,
      TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AS final_48h_start
    FROM
      cohort
  ),
  insulin_prescriptions AS (
    SELECT
      p.subject_id,
      p.hadm_id,
      p.starttime,
      p.drug,
      CASE
        WHEN LOWER(p.drug) LIKE '%glargine%' OR LOWER(p.drug) LIKE '%detemir%' OR LOWER(p.drug) LIKE '%nph%' THEN 'basal'
        WHEN LOWER(p.drug) LIKE '%aspart%' OR LOWER(p.drug) LIKE '%lispro%' OR LOWER(p.drug) LIKE '%regular%' THEN 'bolus'
        ELSE NULL
      END AS regimen_type
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE
      LOWER(p.drug) LIKE '%insulin%'
      AND p.drug NOT LIKE '%sliding scale%'
  ),
  sliding_scale_orders AS (
    SELECT
      e.subject_id,
      e.hadm_id,
      e.charttime AS starttime,
      'sliding_scale' AS regimen_type
    FROM
      `physionet-data.mimiciv_3_1_hosp.emar` e
    WHERE
      LOWER(e.event_txt) LIKE '%sliding scale%'
  ),
  all_insulin_orders AS (
    SELECT subject_id, hadm_id, starttime, regimen_type FROM insulin_prescriptions
    UNION ALL
    SELECT subject_id, hadm_id, starttime, regimen_type FROM sliding_scale_orders
  ),
  regimen_types AS (
    SELECT 'basal' AS regimen_type
    UNION ALL SELECT 'bolus'
    UNION ALL SELECT 'sliding_scale'
  ),
  cohort_regimens AS (
    SELECT
      c.subject_id,
      c.hadm_id,
      c.admittime,
      c.dischtime,
      c.first_72h_end,
      c.final_48h_start,
      rt.regimen_type
    FROM
      admission_periods c
    CROSS JOIN
      regimen_types rt
  ),
  cohort_regimens_orders AS (
    SELECT
      cr.subject_id,
      cr.hadm_id,
      cr.regimen_type,
      cr.admittime,
      cr.dischtime,
      cr.first_72h_end,
      cr.final_48h_start,
      MAX(CASE WHEN o.starttime BETWEEN cr.admittime AND cr.first_72h_end THEN 1 ELSE 0 END) AS initiated_first_72h,
      MAX(CASE WHEN o.starttime BETWEEN cr.final_48h_start AND cr.dischtime THEN 1 ELSE 0 END) AS initiated_final_48h
    FROM
      cohort_regimens cr
    LEFT JOIN
      all_insulin_orders o
      ON cr.subject_id = o.subject_id
      AND cr.hadm_id = o.hadm_id
      AND cr.regimen_type = o.regimen_type
    GROUP BY
      cr.subject_id, cr.hadm_id, cr.regimen_type, cr.admittime, cr.dischtime, cr.first_72h_end, cr.final_48h_start
  ),
  aggregated AS (
    SELECT
      regimen_type,
      'first_72h' AS period,
      SUM(initiated_first_72h) AS num_initiated,
      COUNT(*) AS total_patients
    FROM
      cohort_regimens_orders
    GROUP BY
      regimen_type
    UNION ALL
    SELECT
      regimen_type,
      'final_48h' AS period,
      SUM(initiated_final_48h) AS num_initiated,
      COUNT(*) AS total_patients
    FROM
      cohort_regimens_orders
    GROUP BY
      regimen_type
  ),
  percentages AS (
    SELECT
      regimen_type,
      period,
      num_initiated,
      total_patients,
      ROUND(100.0 * num_initiated / total_patients, 2) AS percent_initiated
    FROM
      aggregated
  ),
  pivoted AS (
    SELECT
      regimen_type,
      MAX(CASE WHEN period = 'first_72h' THEN percent_initiated END) AS percent_first_72h,
      MAX(CASE WHEN period = 'final_48h' THEN percent_initiated END) AS percent_final_48h
    FROM
      percentages
    GROUP BY
      regimen_type
  ),
  final_output AS (
    SELECT
      regimen_type,
      percent_first_72h,
      percent_final_48h,
      ROUND(ABS(percent_first_72h - percent_final_48h), 2) AS abs_diff
    FROM
      pivoted
  )
SELECT * FROM final_output;