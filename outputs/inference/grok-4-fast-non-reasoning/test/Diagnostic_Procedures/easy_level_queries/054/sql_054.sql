WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 81 AND 91
),
echo_procedures AS (
  SELECT p.subject_id, pr.hadm_id, COUNT(DISTINCT pr.icd_code) AS distinct_echo_count
  FROM eligible_patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pr.icd_code = d.icd_code
    AND pr.icd_version = d.icd_version
    AND pr.icd_version = 10
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.subject_id = a.subject_id
    AND pr.hadm_id = a.hadm_id
  WHERE LOWER(d.long_title) LIKE '%echocardiography%'
     OR LOWER(d.long_title) LIKE '%echo%'
  GROUP BY p.subject_id, pr.hadm_id
)
SELECT MAX(distinct_echo_count) AS max_distinct_echo_procedures
FROM echo_procedures
WHERE subject_id IN (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age = 86
)
  AND hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON a.subject_id = pat.subject_id
    WHERE pat.gender = 'F' AND pat.anchor_age = 86
  );