WITH stroke_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
      ON d.icd_code    = icd.icd_code
      AND d.icd_version = icd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 94
    AND LOWER(icd.long_title) LIKE '%ischemic%'
    AND LOWER(icd.long_title) LIKE '%stroke%'
)
SELECT
  -- 25th percentile of serum glucose on discharge day
  APPROX_QUANTILES(l.valuenum, 100)[OFFSET(25)] AS glucose_p25,
  -- 75th percentile of serum glucose on discharge day
  APPROX_QUANTILES(l.valuenum, 100)[OFFSET(75)] AS glucose_p75
FROM
  stroke_admissions sa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON sa.subject_id = l.subject_id
    AND sa.hadm_id    = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
WHERE
  l.valuenum IS NOT NULL
  AND LOWER(li.label) LIKE '%glucose%'
  AND LOWER(li.fluid) = 'serum'
  AND DATE(l.charttime) = DATE(sa.dischtime);