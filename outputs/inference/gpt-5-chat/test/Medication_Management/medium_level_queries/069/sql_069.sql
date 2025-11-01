WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  -- Demographics filter
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
),
t2dm AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE ( (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
       OR (d.icd_version = 9 AND (d.icd_code LIKE '250%') AND 
             SUBSTR(d.icd_code,6,1) IN ('0','2') ) )
),
hf AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE ( (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
       OR (d.icd_version = 9 AND d.icd_code LIKE '428%') )
),
cohort_with_dx AS (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime
  FROM cohort c
  JOIN t2dm t ON c.subject_id = t.subject_id AND c.hadm_id = t.hadm_id
  JOIN hf h ON c.subject_id = h.subject_id AND c.hadm_id = h.hadm_id
),
glp1_rx AS (
  SELECT DISTINCT pr.subject_id, pr.hadm_id, pr.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE LOWER(pr.drug) LIKE '%exenatide%'
     OR LOWER(pr.drug) LIKE '%liraglutide%'
     OR LOWER(pr.drug) LIKE '%semaglutide%'
     OR LOWER(pr.drug) LIKE '%dulaglutide%'
     OR LOWER(pr.drug) LIKE '%albiglutide%'
     OR LOWER(pr.drug) LIKE '%lixisenatide%'
)
SELECT
  COUNT(DISTINCT cwd.hadm_id) AS total_admissions,
  COUNT(DISTINCT CASE WHEN TIMESTAMP_DIFF(gl.starttime, cwd.admittime, HOUR) <= 12 THEN cwd.hadm_id END) AS num_first12h,
  COUNT(DISTINCT CASE WHEN TIMESTAMP_DIFF(cwd.dischtime, gl.starttime, HOUR) <= 12 THEN cwd.hadm_id END) AS num_final12h,
  SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN TIMESTAMP_DIFF(gl.starttime, cwd.admittime, HOUR) <= 12 THEN cwd.hadm_id END), COUNT(DISTINCT cwd.hadm_id)) * 100 AS pct_first12h,
  SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN TIMESTAMP_DIFF(cwd.dischtime, gl.starttime, HOUR) <= 12 THEN cwd.hadm_id END), COUNT(DISTINCT cwd.hadm_id)) * 100 AS pct_final12h,
  SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN TIMESTAMP_DIFF(cwd.dischtime, gl.starttime, HOUR) <= 12 THEN cwd.hadm_id END), COUNT(DISTINCT cwd.hadm_id)) * 100
  - SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN TIMESTAMP_DIFF(gl.starttime, cwd.admittime, HOUR) <= 12 THEN cwd.hadm_id END), COUNT(DISTINCT cwd.hadm_id)) * 100 AS net_change_pct
FROM cohort_with_dx cwd
LEFT JOIN glp1_rx gl 
  ON cwd.subject_id = gl.subject_id AND cwd.hadm_id = gl.hadm_id;