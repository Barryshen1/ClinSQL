WITH qualifying_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, TIMESTAMP(a.dischtime) AS disch_ts
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND SAFE_CAST(p.anchor_age AS INT64) = 87
    AND d.icd_version = '10'
    AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%')
    AND a.dischtime IS NOT NULL
),
discharge_labs AS (
  SELECT qp.subject_id, qp.hadm_id, l.valuenum
  FROM qualifying_patients qp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON qp.subject_id = l.subject_id AND qp.hadm_id = l.hadm_id
  WHERE l.itemid = 50592  -- Platelet count
    AND l.valuenum IS NOT NULL
    AND DATE(l.charttime) = DATE(qp.disch_ts)
)
SELECT
  PERCENTILE_CONT(0.75, valuenum) OVER() AS p75_platelet_count
FROM discharge_labs;