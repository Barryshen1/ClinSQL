WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 81 AND 91
),

admissions_with_diagnosis AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.los -- Fix: Added 'a.los' to the SELECT list
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN filtered_patients fp ON a.subject_id = fp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (
    (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '78650'))
    OR
    (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code = 'R079'))
  )
),

index_troponin AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%' AND LOWER(dl.label) LIKE '%high%sensitiv%'
    AND le.valuenum IS NOT NULL
),

first_troponin AS (
  SELECT hadm_id, valuenum
  FROM index_troponin
  WHERE rn = 1
),

troponin_category AS (
  SELECT
    hadm_id,
    CASE
      WHEN valuenum < 14 THEN 'Normal'
      WHEN valuenum >= 14 AND valuenum < 20 THEN 'Borderline'
      WHEN valuenum >= 20 THEN 'Myocardial Injury'
      ELSE 'Unknown'
    END AS troponin_group
  FROM first_troponin
)

SELECT
  tc.troponin_group,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(a.los), 2) AS mean_los
FROM troponin_category tc
JOIN admissions_with_diagnosis a ON tc.hadm_id = a.hadm_id
GROUP BY tc.troponin_group
ORDER BY
  CASE tc.troponin_group
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
    ELSE 4
  END;