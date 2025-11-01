WITH stroke_patients AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age >= 49 AND p.anchor_age <= 59
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '434%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
),
lab_instability AS (
  SELECT
    sp.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM stroke_patients sp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON sp.hadm_id = l.hadm_id
  WHERE l.charttime >= sp.admittime
    AND l.charttime <= DATETIME_ADD(sp.admittime, INTERVAL 72 HOUR)
    AND LOWER(COALESCE(l.flag, '')) = 'abnormal'
    AND l.valuenum IS NOT NULL
  GROUP BY sp.hadm_id
)
SELECT
  APPROX_QUANTILES(abnormal_lab_count, 1000)[OFFSET(750)] AS lab_instability_score_75th_percentile
FROM lab_instability;