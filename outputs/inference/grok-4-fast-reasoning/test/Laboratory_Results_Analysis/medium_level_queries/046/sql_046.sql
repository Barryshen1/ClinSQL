WITH initial_trop AS (
  SELECT 
    hadm_id, 
    valuenum AS initial_trop
  FROM (
    SELECT 
      hadm_id, 
      valuenum, 
      charttime,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid = 50922 
      AND valuenum IS NOT NULL 
      AND valuenum > 0.01
  ) 
  WHERE rn = 1
),
qualifying_adms AS (
  SELECT 
    a.subject_id, 
    p.anchor_age, 
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    it.initial_trop,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime ASC) AS rn_subj
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN initial_trop it 
    ON a.hadm_id = it.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I21%'
    )
)
SELECT 
  COUNT(*) AS N,
  ROUND(AVG(anchor_age), 2) AS mean_age,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(AVG(initial_trop), 4) AS mean_initial_troponin,
  ROUND(MIN(initial_trop), 4) AS min_initial_troponin,
  ROUND(MAX(initial_trop), 4) AS max_initial_troponin
FROM qualifying_adms
WHERE rn_subj = 1;