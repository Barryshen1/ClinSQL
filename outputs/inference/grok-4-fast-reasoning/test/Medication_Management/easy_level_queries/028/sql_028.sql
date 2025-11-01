WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.hadm_id IS NOT NULL
),
dapt_hadms AS (
  SELECT pr.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.drug IN ('Aspirin', 'Clopidogrel', 'Prasugrel', 'Ticagrelor')
  GROUP BY pr.hadm_id
  HAVING SUM(CASE WHEN pr.drug = 'Aspirin' THEN 1 ELSE 0 END) > 0
     AND SUM(CASE WHEN pr.drug IN ('Clopidogrel', 'Prasugrel', 'Ticagrelor') THEN 1 ELSE 0 END) > 0
)
SELECT STDDEV(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY)) AS sd_single_antiplatelet_duration_days
FROM dapt_hadms dh
INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON dh.hadm_id = pr.hadm_id
WHERE pr.drug IN ('Aspirin', 'Clopidogrel', 'Prasugrel', 'Ticagrelor')
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL;