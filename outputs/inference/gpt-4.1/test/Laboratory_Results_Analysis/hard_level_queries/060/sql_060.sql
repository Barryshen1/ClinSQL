WITH cardiac_arrest_icd AS (
  -- ICD-9: 427.5, ICD-10: I46.x
  SELECT DISTINCT d.icd_code, d.icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  WHERE (d.icd_version = 9 AND d.icd_code = '4275')
     OR (d.icd_version = 10 AND (d.icd_code LIKE 'I46%' OR d.icd_code LIKE 'I490%'))
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN cardiac_arrest_icd ca
    ON d.icd_code = ca.icd_code AND d.icd_version = ca.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),
critical_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.itemid,
    l.flag,
    l.valuenum,
    l.valueuom,
    l.ref_range_lower,
    l.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
),
cohort_labs_48h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    l.charttime,
    l.itemid,
    l.flag,
    l.valuenum,
    l.valueuom,
    l.ref_range_lower,
    l.ref_range_upper
  FROM cohort c
  JOIN critical_labs l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  WHERE TIMESTAMP_DIFF(l.charttime, c.admittime, HOUR) BETWEEN 0 AND 48
),
cohort_instability AS (
  SELECT
    cl.subject_id,
    cl.hadm_id,
    COUNTIF(
      (cl.flag = 'abnormal')
      OR (cl.ref_range_lower IS NOT NULL AND cl.ref_range_upper IS NOT NULL AND cl.valuenum IS NOT NULL AND
          (cl.valuenum < cl.ref_range_lower OR cl.valuenum > cl.ref_range_upper))
    ) AS instability_score
  FROM cohort_labs_48h cl
  GROUP BY cl.subject_id, cl.hadm_id
),
cohort_summary AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    IFNULL(ci.instability_score, 0) AS instability_score,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR)/24.0 AS los_days,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN cohort_instability ci
    ON c.subject_id = ci.subject_id AND c.hadm_id = ci.hadm_id
),
general_labs_48h AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    l.charttime,
    l.itemid,
    l.flag,
    l.valuenum,
    l.valueuom,
    l.ref_range_lower,
    l.ref_range_upper,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  WHERE TIMESTAMP_DIFF(l.charttime, a.admittime, HOUR) BETWEEN 0 AND 48
),
general_instability AS (
  SELECT
    gl.subject_id,
    gl.hadm_id,
    COUNTIF(
      (gl.flag = 'abnormal')
      OR (gl.ref_range_lower IS NOT NULL AND gl.ref_range_upper IS NOT NULL AND gl.valuenum IS NOT NULL AND
          (gl.valuenum < gl.ref_range_lower OR gl.valuenum > gl.ref_range_upper))
    ) AS instability_score
  FROM general_labs_48h gl
  GROUP BY gl.subject_id, gl.hadm_id
),
general_summary AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    IFNULL(gi.instability_score, 0) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN general_instability gi
    ON a.subject_id = gi.subject_id AND a.hadm_id = gi.hadm_id
)
-- Final output
SELECT
  'Cohort (Females 52-62 post-cardiac arrest)' AS group_name,
  APPROX_QUANTILES(instability_score, 4)[1] AS instability_score_Q1,
  APPROX_QUANTILES(instability_score, 4)[2] AS instability_score_median,
  APPROX_QUANTILES(los_days, 2)[1] AS los_median_days,
  ROUND(SUM(hospital_expire_flag)/COUNT(*), 3) AS mortality_rate
FROM cohort_summary

UNION ALL

SELECT
  'General inpatients' AS group_name,
  APPROX_QUANTILES(instability_score, 4)[1] AS instability_score_Q1,
  APPROX_QUANTILES(instability_score, 4)[2] AS instability_score_median,
  NULL AS los_median_days,
  NULL AS mortality_rate
FROM general_summary;