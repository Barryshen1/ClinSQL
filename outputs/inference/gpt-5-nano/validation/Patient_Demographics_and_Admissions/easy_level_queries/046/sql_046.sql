WITH ranked_admissions AS (
  SELECT
    a.*,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
),
first_admissions AS (
  SELECT subject_id, hadm_id
  FROM ranked_admissions
  WHERE rn = 1
),
dapt_flags AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    MAX(IF(LOWER(pr.drug) LIKE '%aspirin%', 1, 0)) AS has_aspirin,
    MAX(
      IF(
        LOWER(pr.drug) LIKE '%clopidogrel%' OR
        LOWER(pr.drug) LIKE '%prasugrel%' OR
        LOWER(pr.drug) LIKE '%ticagrelor%', 1, 0
      )
    ) AS has_p2y12
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pr.subject_id = a.subject_id AND pr.hadm_id = a.hadm_id
  GROUP BY a.subject_id, a.hadm_id
),
eligible AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN first_admissions AS f
    ON a.subject_id = f.subject_id AND a.hadm_id = f.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON a.subject_id = pat.subject_id
  JOIN dapt_flags AS d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE d.has_aspirin = 1
    AND d.has_p2y12 = 1
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 37 AND 47
)
SELECT STDDEV_POP(hospital_expire_flag) AS sd_in_hospital_mortality
FROM eligible;