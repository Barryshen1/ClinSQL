WITH cr_items AS (
  -- Identify lab itemids corresponding to (serum/plasma) creatinine by label text
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
),

hf_admissions AS (
  -- Male, age 66 admissions with any diagnosis whose description indicates heart failure
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 66
    AND LOWER(dicd.long_title) LIKE '%heart failure%'
),

creat_24h_per_adm AS (
  -- For each HF admission, compute the maximum creatinine in the first 24 hours after admission
  SELECT
    l.subject_id,
    l.hadm_id,
    MAX(COALESCE(l.valuenum, SAFE_CAST(l.value AS FLOAT64))) AS max_creat24,
    ANY_VALUE(l.valueuom) AS valueuom
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN cr_items ci
    ON l.itemid = ci.itemid
  JOIN hf_admissions ha
    ON l.subject_id = ha.subject_id AND l.hadm_id = ha.hadm_id
  WHERE l.charttime IS NOT NULL
    AND l.charttime BETWEEN ha.admittime AND TIMESTAMP_ADD(ha.admittime, INTERVAL 24 HOUR)
    AND (l.valuenum IS NOT NULL OR SAFE_CAST(l.value AS FLOAT64) IS NOT NULL)
  GROUP BY l.subject_id, l.hadm_id
)

-- Return the single admission (and patient) with the highest admission (first 24h) creatinine
SELECT
  c.hadm_id,
  c.subject_id,
  c.max_creat24 AS max_creatinine_first_24h,
  c.valueuom
FROM creat_24h_per_adm c
ORDER BY c.max_creat24 DESC
LIMIT 1;