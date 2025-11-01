WITH qualifying_admissions AS (
  SELECT 
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) = 50
    AND p.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE 
        d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%chronic obstructive pulmonary disease%'
    )
),
nadir_sodium AS (
  SELECT 
    MIN(l.valuenum) AS nadir_val
  FROM qualifying_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON qa.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE 
    d.fluid = 'Blood'
    AND LOWER(d.label) LIKE '%sodium%'
    AND l.valuenum IS NOT NULL
  GROUP BY qa.hadm_id
)
SELECT 
  STDDEV(nadir_val) AS std_nadir_sodium
FROM nadir_sodium;