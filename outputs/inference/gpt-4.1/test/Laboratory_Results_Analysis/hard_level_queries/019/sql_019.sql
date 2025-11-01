WITH ap_admissions AS (
  -- Identify male inpatients aged 63-73 with acute pancreatitis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 63 AND 73
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '5770') -- ICD-9 AP
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%') -- ICD-10 AP
      OR LOWER(dicd.long_title) LIKE '%acute pancreatitis%'
    )
),

lab_instability AS (
  -- For each AP admission, count critical labs in first 72h
  SELECT
    ap.subject_id,
    ap.hadm_id,
    ap.admittime,
    ap.dischtime,
    ap.hospital_expire_flag,
    COUNTIF(
      (
        le.flag = 'abnormal'
        OR (
          SAFE_CAST(le.valuenum AS FLOAT64) IS NOT NULL
          AND (
            (le.ref_range_lower IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) < SAFE_CAST(le.ref_range_lower AS FLOAT64))
            OR (le.ref_range_upper IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) > SAFE_CAST(le.ref_range_upper AS FLOAT64))
          )
        )
      )
    ) AS lab_instability_score
  FROM
    ap_admissions ap
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON ap.hadm_id = le.hadm_id
      AND le.charttime >= ap.admittime
      AND le.charttime < TIMESTAMP_ADD(ap.admittime, INTERVAL 72 HOUR)
  GROUP BY
    ap.subject_id, ap.hadm_id, ap.admittime, ap.dischtime, ap.hospital_expire_flag
),

p90_score AS (
  -- Compute 90th percentile of lab-instability score
  SELECT
    PERCENTILE_CONT(lab_instability_score, 0.9) OVER() AS p90_lab_instability
  FROM
    lab_instability
  LIMIT 1
),

ap_p90_group AS (
  -- Admissions with lab-instability score >= P90
  SELECT
    li.*,
    p90.p90_lab_instability
  FROM
    lab_instability li
    CROSS JOIN p90_score p90
  WHERE
    li.lab_instability_score >= p90.p90_lab_instability
),

ap_p90_lab_critical_rates AS (
  -- Per-lab critical rates in AP P90 group (first 72h)
  SELECT
    dlab.label AS lab_name,
    COUNT(*) AS total_results,
    COUNTIF(
      (
        le.flag = 'abnormal'
        OR (
          SAFE_CAST(le.valuenum AS FLOAT64) IS NOT NULL
          AND (
            (le.ref_range_lower IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) < SAFE_CAST(le.ref_range_lower AS FLOAT64))
            OR (le.ref_range_upper IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) > SAFE_CAST(le.ref_range_upper AS FLOAT64))
          )
        )
      )
    ) AS critical_results,
    SAFE_DIVIDE(
      COUNTIF(
        (
          le.flag = 'abnormal'
          OR (
            SAFE_CAST(le.valuenum AS FLOAT64) IS NOT NULL
            AND (
              (le.ref_range_lower IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) < SAFE_CAST(le.ref_range_lower AS FLOAT64))
              OR (le.ref_range_upper IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) > SAFE_CAST(le.ref_range_upper AS FLOAT64))
            )
          )
        )
      ),
      COUNT(*)
    ) AS critical_rate
  FROM
    ap_p90_group ap
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON ap.hadm_id = le.hadm_id
      AND le.charttime >= ap.admittime
      AND le.charttime < TIMESTAMP_ADD(ap.admittime, INTERVAL 72 HOUR)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
      ON le.itemid = dlab.itemid
  GROUP BY
    dlab.label
),

general_lab_critical_rates AS (
  -- Per-lab critical rates in all inpatients (first 72h)
  SELECT
    dlab.label AS lab_name,
    COUNT(*) AS total_results,
    COUNTIF(
      (
        le.flag = 'abnormal'
        OR (
          SAFE_CAST(le.valuenum AS FLOAT64) IS NOT NULL
          AND (
            (le.ref_range_lower IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) < SAFE_CAST(le.ref_range_lower AS FLOAT64))
            OR (le.ref_range_upper IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) > SAFE_CAST(le.ref_range_upper AS FLOAT64))
          )
        )
      )
    ) AS critical_results,
    SAFE_DIVIDE(
      COUNTIF(
        (
          le.flag = 'abnormal'
          OR (
            SAFE_CAST(le.valuenum AS FLOAT64) IS NOT NULL
            AND (
              (le.ref_range_lower IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) < SAFE_CAST(le.ref_range_lower AS FLOAT64))
              OR (le.ref_range_upper IS NOT NULL AND SAFE_CAST(le.valuenum AS FLOAT64) > SAFE_CAST(le.ref_range_upper AS FLOAT64))
            )
          )
        )
      ),
      COUNT(*)
    ) AS critical_rate
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON adm.hadm_id = le.hadm_id
      AND le.charttime >= adm.admittime
      AND le.charttime < TIMESTAMP_ADD(adm.admittime, INTERVAL 72 HOUR)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
      ON le.itemid = dlab.itemid
  GROUP BY
    dlab.label
),

ap_p90_summary AS (
  -- Mortality and mean LOS for AP P90 group
  SELECT
    COUNT(*) AS n_admissions,
    SUM(CAST(hospital_expire_flag AS INT64)) AS n_deaths,
    SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) AS mean_los_days
  FROM
    ap_p90_group
)

-- Final output: P90 value, summary stats, per-lab critical rates for AP P90 group and general inpatients
SELECT
  p90.p90_lab_instability AS lab_instability_score_p90,
  ap_p90_summary.n_admissions,
  ap_p90_summary.n_deaths,
  ap_p90_summary.mortality_rate,
  ap_p90_summary.mean_los_days,
  ap_lab.lab_name,
  ap_lab.critical_rate AS ap_p90_critical_rate,
  gen_lab.critical_rate AS general_critical_rate
FROM
  p90_score p90
  CROSS JOIN ap_p90_summary
  LEFT JOIN ap_p90_lab_critical_rates ap_lab
    ON TRUE
  LEFT JOIN general_lab_critical_rates gen_lab
    ON ap_lab.lab_name = gen_lab.lab_name
ORDER BY
  ap_lab.lab_name;