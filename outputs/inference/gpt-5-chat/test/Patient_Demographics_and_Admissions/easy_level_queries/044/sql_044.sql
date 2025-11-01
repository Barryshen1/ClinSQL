WITH first_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      hospital_expire_flag,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ) a
  ON p.subject_id = a.subject_id
  WHERE a.rn = 1
)
SELECT
  PERCENTILE_CONT(hospital_expire_flag, 0.25) OVER() AS p25_mortality
FROM first_admissions
WHERE gender = 'M'
  AND anchor_age BETWEEN 73 AND 83;