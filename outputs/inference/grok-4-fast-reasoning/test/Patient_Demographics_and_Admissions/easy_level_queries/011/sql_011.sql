WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 76 AND 86
),
first_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients ep ON a.subject_id = ep.subject_id
),
first_hadms AS (
  SELECT subject_id, hadm_id
  FROM first_admissions
  WHERE rn = 1
),
dapt_first_adms AS (
  SELECT pr.subject_id, pr.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN first_hadms fh ON pr.subject_id = fh.subject_id AND pr.hadm_id = fh.hadm_id
  WHERE LOWER(pr.drug) LIKE '%aspirin%'
     OR LOWER(pr.drug) LIKE '%clopidogrel%'
     OR LOWER(pr.drug) LIKE '%prasugrel%'
     OR LOWER(pr.drug) LIKE '%ticagrelor%'
  GROUP BY pr.subject_id, pr.hadm_id
  HAVING COUNT(DISTINCT CASE WHEN LOWER(pr.drug) LIKE '%aspirin%' THEN 'aspirin' END) > 0
     AND COUNT(DISTINCT 
       CASE 
         WHEN LOWER(pr.drug) LIKE '%clopidogrel%' 
           OR LOWER(pr.drug) LIKE '%prasugrel%' 
           OR LOWER(pr.drug) LIKE '%ticagrelor%' 
         THEN 'p2y12' 
       END
     ) > 0
),
icu_los AS (
  SELECT dfa.subject_id, dfa.hadm_id, SUM(i.los) AS total_icu_los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN dapt_first_adms dfa ON i.subject_id = dfa.subject_id AND i.hadm_id = dfa.hadm_id
  GROUP BY dfa.subject_id, dfa.hadm_id
)
SELECT AVG(total_icu_los) AS avg_icu_los_days
FROM icu_los;