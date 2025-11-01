WITH pe_patients AS (
  SELECT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%pulmonary embolism%'
),

male_81_91 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 81 AND 91
),

pe_males_81_91 AS (
  SELECT p.subject_id, p.hadm_id
  FROM pe_patients p
  JOIN male_81_91 m ON p.subject_id = m.subject_id
),

charlson_scores AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    SUM(
      CASE
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '410%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '428%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '496%') OR (d.icd_version = 10 AND d.icd_code LIKE 'J44%') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '43%') OR (d.icd_version = 10 AND d.icd_code LIKE 'I6%') THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '250%') AND d.icd_code NOT LIKE '250.4%' THEN 1
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '250.4%') OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10.4%' OR d.icd_code LIKE 'E11.4%')) THEN 2
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '585%') OR (d.icd_version = 10 AND d.icd_code LIKE 'N18%') THEN 2
        WHEN (d.icd_version = 9 AND d.icd_code LIKE '140%') OR (d.icd_version = 10 AND d.icd_code LIKE 'C%') THEN 2
        ELSE 0
      END
    ) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  GROUP BY d.subject_id, d.hadm_id
),

p75 AS (
  SELECT APPROX_QUANTILES(charlson_score, 100)[OFFSET(75)] AS p75
  FROM charlson_scores
),

mortality AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    CASE
      WHEN p.dod IS NOT NULL AND p.dod <= DATE_ADD(a.admittime, INTERVAL 90 DAY) THEN 1
      ELSE 0
    END AS died_90_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
)

SELECT
  AVG(c.charlson_score) AS mean_risk_score,
  AVG(m.died_90_days) AS ninety_day_mortality
FROM charlson_scores c
JOIN pe_males_81_91 pm ON c.subject_id = pm.subject_id AND c.hadm_id = pm.hadm_id
JOIN mortality m ON c.subject_id = m.subject_id AND c.hadm_id = m.hadm_id
WHERE c.charlson_score > (SELECT p75 FROM p75);