WITH first_admissions AS (
  -- determine the first admission per subject
  SELECT a.subject_id, a.hadm_id
  FROM (
    SELECT subject_id, MIN(admittime) AS first_admit
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY subject_id
  ) m
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.subject_id = m.subject_id AND a.admittime = m.first_admit
),
cabg_on_first AS (
  -- keep only those first admissions where CABG occurred
  SELECT DISTINCT f.subject_id, f.hadm_id
  FROM first_admissions f
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON pat.subject_id = f.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON pr.subject_id = f.subject_id AND pr.hadm_id = f.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON d.icd_code = pr.icd_code AND d.icd_version = pr.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 35 AND 45
    AND LOWER(d.long_title) LIKE '%cabg%'
)
SELECT
  COUNT(*) AS cohort_size,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_deaths
FROM cabg_on_first c
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id;