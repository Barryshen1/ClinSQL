WITH hhs_flag AS (
  SELECT
    hadm_id,
    MAX(
      CASE
        WHEN (icd_version = 10 AND (STARTS_WITH(icd_code, 'E11.0') OR STARTS_WITH(icd_code, 'E10.0')))
          OR (icd_version = 9 AND (STARTS_WITH(icd_code, '250.2')))
        THEN 1 ELSE 0
      END
    ) AS is_hhs
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
icu_cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.gender,
    pat.anchor_age,
    adm.hospital_expire_flag,
    icu.intime,
    icu.outtime,
    icu.los,
    COALESCE(hhs.is_hhs, 0) AS is_hhs
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  LEFT JOIN hhs_flag hhs
    ON icu.hadm_id = hhs.hadm_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 78 AND 88
),
-- Vital signs in first 48h
vitals_48h AS (
  SELECT
    c.stay_id,
    SUM(
      CASE WHEN di.label = 'Heart Rate' AND (c.valuenum < 50 OR c.valuenum > 120) THEN 1 ELSE 0 END
      + CASE WHEN di.label = 'Mean BP' AND c.valuenum < 65 THEN 1 ELSE 0 END
      + CASE WHEN di.label = 'Temperature Celsius' AND (c.valuenum < 36 OR c.valuenum > 38) THEN 1 ELSE 0 END
    ) AS composite_instability_score,
    AVG(
      CASE WHEN di.label IN ('Heart Rate','Mean BP','Temperature Celsius')
            AND (
              (di.label = 'Heart Rate' AND (c.valuenum < 50 OR c.valuenum > 120))
              OR (di.label = 'Mean BP' AND c.valuenum < 65)
              OR (di.label = 'Temperature Celsius' AND (c.valuenum < 36 OR c.valuenum > 38))
            )
          THEN 1 ELSE 0 END
    ) AS abnormal_vital_burden
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  JOIN icu_cohort co
    ON c.stay_id = co.stay_id
  WHERE c.charttime BETWEEN co.intime AND TIMESTAMP_ADD(co.intime, INTERVAL 48 HOUR)
    AND di.label IN ('Heart Rate','Mean BP','Temperature Celsius')
    AND c.valuenum IS NOT NULL
  GROUP BY c.stay_id
),
-- Combine all measures
measures AS (
  SELECT
    co.is_hhs,
    v.composite_instability_score,
    v.abnormal_vital_burden,
    co.los,
    co.hospital_expire_flag
  FROM icu_cohort co
  LEFT JOIN vitals_48h v
    ON co.stay_id = v.stay_id
)
SELECT
  CASE WHEN is_hhs = 1 THEN 'HHS' ELSE 'Control' END AS group_label,
  -- Composite instability score percentiles
  APPROX_QUANTILES(composite_instability_score, 4)[OFFSET(1)] AS pct25_composite_instability,
  APPROX_QUANTILES(composite_instability_score, 4)[OFFSET(2)] AS median_composite_instability,
  APPROX_QUANTILES(composite_instability_score, 4)[OFFSET(3)] AS pct75_composite_instability,
  -- Abnormal vital burden percentiles
  APPROX_QUANTILES(abnormal_vital_burden, 4)[OFFSET(1)] AS pct25_abnormal_vital_burden,
  APPROX_QUANTILES(abnormal_vital_burden, 4)[OFFSET(2)] AS median_abnormal_vital_burden,
  APPROX_QUANTILES(abnormal_vital_burden, 4)[OFFSET(3)] AS pct75_abnormal_vital_burden,
  -- ICU LOS stats
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS pct25_los,
  APPROX_QUANTILES(los, 4)[OFFSET(2)] AS median_los,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS pct75_los,
  -- Mortality mean (proportion)
  AVG(hospital_expire_flag) AS mortality_rate
FROM measures
GROUP BY is_hhs;