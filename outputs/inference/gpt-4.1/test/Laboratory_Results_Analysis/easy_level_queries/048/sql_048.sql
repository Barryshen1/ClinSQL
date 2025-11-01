WITH copd_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.patients p
      ON a.subject_id = p.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 56
    AND (
      (d.icd_version = 9 AND d.icd_code = '496')
      OR (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'J44')
    )
),
creatinine_items AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_hosp.d_labitems
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(fluid) = 'serum'
),
creatinine_first24h AS (
  SELECT
    ca.hadm_id,
    AVG(le.valuenum) AS avg_creatinine
  FROM
    copd_admissions ca
    JOIN physionet-data.mimiciv_3_1_hosp.labevents le
      ON ca.hadm_id = le.hadm_id
    JOIN creatinine_items ci
      ON le.itemid = ci.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime >= ca.admittime
    AND le.charttime < DATETIME_ADD(ca.admittime, INTERVAL 24 HOUR)
  GROUP BY
    ca.hadm_id
)
SELECT
  APPROX_QUANTILES(avg_creatinine, 4)[OFFSET(3)] AS creatinine_75th_percentile
FROM
  creatinine_first24h
WHERE
  avg_creatinine IS NOT NULL
;