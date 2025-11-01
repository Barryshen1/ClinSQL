WITH stroke_adm AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age = 94
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
      OR (d.icd_version = 9 AND (
             (d.icd_code LIKE '433%' AND RIGHT(d.icd_code,1) = '1')
          OR (d.icd_code LIKE '434%' AND RIGHT(d.icd_code,1) = '1')
         )
      )
    )
),
glucose_labs AS (
  SELECT
    la.valuenum
  FROM stroke_adm sa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` la
    ON sa.hadm_id = la.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON la.itemid = di.itemid
  WHERE la.valuenum IS NOT NULL
    AND LOWER(di.label) LIKE '%glucose%'
    AND LOWER(di.fluid) IN ('blood','serum','plasma')
    AND DATE(la.charttime) = DATE(sa.dischtime)
)
SELECT
  percentile_cont(valuenum, 0.25) OVER() AS q1,
  percentile_cont(valuenum, 0.75) OVER() AS q3,
  percentile_cont(valuenum, 0.75) OVER()
    - percentile_cont(valuenum, 0.25) OVER() AS iqr
FROM glucose_labs
LIMIT 1;