WITH male_age AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 37 AND 47
),
first_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN male_age m ON a.subject_id = m.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),
antiplatelet_prescriptions AS (
  SELECT DISTINCT p.subject_id, p.hadm_id,
    LOWER(p.drug) AS drug_lower
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE LOWER(p.drug) LIKE '%aspirin%'
     OR LOWER(p.drug) LIKE '%clopidogrel%'
     OR LOWER(p.drug) LIKE '%prasugrel%'
     OR LOWER(p.drug) LIKE '%ticagrelor%'
),
dapt_first AS (
  SELECT fa.subject_id, fa.hadm_id, fa.hospital_expire_flag
  FROM first_admissions fa
  JOIN antiplatelet_prescriptions ap ON fa.subject_id = ap.subject_id
                                    AND fa.hadm_id = ap.hadm_id
  GROUP BY fa.subject_id, fa.hadm_id, fa.hospital_expire_flag
  HAVING COUNT(DISTINCT ap.drug_lower) >= 2
)
SELECT STDDEV(CAST(hospital_expire_flag AS FLOAT64)) AS sd_in_hosp_mortality
FROM dapt_first;