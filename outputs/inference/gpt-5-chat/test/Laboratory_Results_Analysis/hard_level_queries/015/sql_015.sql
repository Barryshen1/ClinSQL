WITH ischemic_stroke_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND LOWER(dd.long_title) LIKE '%stroke%'
    AND LOWER(dd.long_title) LIKE '%isch%'
),
lab_instability AS (
  SELECT
    isp.hadm_id,
    COUNTIF(
      (l.valuenum IS NOT NULL) AND (
        (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
        OR (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
      )
    ) AS abnormal_lab_count
  FROM ischemic_stroke_patients isp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON isp.subject_id = l.subject_id AND isp.hadm_id = l.hadm_id
  WHERE DATETIME_DIFF(l.charttime, isp.admittime, HOUR) BETWEEN 0 AND 72
  GROUP BY isp.hadm_id
),
percentile_calc AS (
  SELECT
    APPROX_QUANTILES(abnormal_lab_count, 4)[OFFSET(3)] AS p75_score
  FROM lab_instability
),
high_instability_group AS (
  SELECT isp.*, li.abnormal_lab_count
  FROM ischemic_stroke_patients isp
  JOIN lab_instability li
    ON isp.hadm_id = li.hadm_id
  CROSS JOIN percentile_calc pc
  WHERE li.abnormal_lab_count >= pc.p75_score
),
controls AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.hadm_id NOT IN (
      SELECT hadm_id FROM ischemic_stroke_patients
    )
),
control_labs AS (
  SELECT
    c.hadm_id,
    COUNTIF(
      (l.valuenum IS NOT NULL) AND (
        (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
        OR (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
      )
    ) AS abnormal_lab_count,
    COUNTIF(l.valuenum IS NOT NULL) AS total_lab_count
  FROM controls c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  WHERE DATETIME_DIFF(l.charttime, c.admittime, HOUR) BETWEEN 0 AND 72
  GROUP BY c.hadm_id
),
-- Precompute per-admission abnormal rates for high instability group
high_instability_rates AS (
  SELECT
    hig.hadm_id,
    hig.abnormal_lab_count / NULLIF(COUNTIF(l.valuenum IS NOT NULL), 0) AS abnormal_rate
  FROM high_instability_group hig
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON hig.subject_id = l.subject_id AND hig.hadm_id = l.hadm_id
  WHERE DATETIME_DIFF(l.charttime, hig.admittime, HOUR) BETWEEN 0 AND 72
  GROUP BY hig.hadm_id, hig.abnormal_lab_count
),
critical_lab_rates AS (
  SELECT
    'stroke_high_instability' AS group_type,
    AVG(abnormal_rate) AS avg_abnormal_rate
  FROM high_instability_rates
  GROUP BY group_type
  UNION ALL
  SELECT
    'controls' AS group_type,
    AVG(cl.abnormal_lab_count / NULLIF(cl.total_lab_count, 0)) AS avg_abnormal_rate
  FROM control_labs cl
  GROUP BY group_type
)
SELECT
  pc.p75_score AS seventy_fifth_percentile_score,
  hig.hadm_id,
  DATETIME_DIFF(hig.dischtime, hig.admittime, DAY) AS LOS_days,
  hig.hospital_expire_flag AS mortality_flag,
  cr.group_type,
  cr.avg_abnormal_rate
FROM percentile_calc pc
CROSS JOIN high_instability_group hig
LEFT JOIN critical_lab_rates cr
  ON cr.group_type = 'stroke_high_instability'
UNION ALL
SELECT
  pc.p75_score,
  NULL, NULL, NULL,
  cr.group_type,
  cr.avg_abnormal_rate
FROM percentile_calc pc
JOIN critical_lab_rates cr
WHERE cr.group_type = 'controls'
ORDER BY group_type, hadm_id;