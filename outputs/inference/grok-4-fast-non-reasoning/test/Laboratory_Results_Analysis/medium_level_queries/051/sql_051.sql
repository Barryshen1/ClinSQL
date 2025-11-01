WITH acs_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
    AND (icd_code = 'I20.0' OR icd_code LIKE 'I21.%')
),
patients_acs AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN acs_codes c
    ON d.icd_code = c.icd_code AND d.icd_version = 10
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    -- First admission per patient to avoid double-counting
    AND a.hadm_id = (
      SELECT MIN(a2.hadm_id)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a.subject_id
    )
),
first_tnt AS (
  SELECT 
    le.hadm_id,
    FIRST_VALUE(le.valuenum) OVER (
      PARTITION BY le.hadm_id 
      ORDER BY le.charttime 
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS first_valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE li.label LIKE '%troponin t%'
    AND li.category = 'Chemistry'
    AND le.valuenum IS NOT NULL
    AND le.hadm_id IN (SELECT hadm_id FROM patients_acs)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) = 1
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM (
  SELECT 
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    DATE_DIFF(pa.dischtime, pa.admittime, DAY) AS los_days,
    ft.first_valuenum,
    CASE 
      WHEN ft.first_valuenum < 14 THEN 'Normal'
      WHEN ft.first_valuenum < 50 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS category
  FROM patients_acs pa
  INNER JOIN first_tnt ft
    ON pa.hadm_id = ft.hadm_id
)
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    ELSE 3
  END;