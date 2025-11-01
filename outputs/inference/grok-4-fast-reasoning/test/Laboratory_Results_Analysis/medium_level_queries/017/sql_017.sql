WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 
       AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '411%' OR d.icd_code LIKE '412%' 
            OR d.icd_code LIKE '413%' OR d.icd_code LIKE '414%'))
      OR
      (d.icd_version = 10 
       AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%' 
            OR d.icd_code LIKE 'I23%' OR d.icd_code LIKE 'I24%' OR d.icd_code LIKE 'I25%'))
    )
),
troponins AS (
  SELECT 
    l.subject_id, 
    l.hadm_id, 
    l.charttime, 
    l.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN 
    cohort c 
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
    ON l.itemid = li.itemid
  WHERE 
    LOWER(li.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/mL'
    AND l.charttime >= c.admittime
    AND l.charttime <= c.dischtime
),
first_trop AS (
  SELECT 
    subject_id, 
    hadm_id, 
    valuenum
  FROM (
    SELECT 
      *, 
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM 
      troponins
  ) 
  WHERE 
    rn = 1 
    AND valuenum > 0.014
)
SELECT 
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS median_troponin,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3,
  (APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)]) AS iqr
FROM 
  first_trop;