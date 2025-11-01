WITH 
  hs_tnt_categories AS (
    SELECT 
      labevent_id,
      subject_id,
      hadm_id,
      charttime,
      valuenum,
      CASE 
        WHEN valuenum < 6 THEN 'normal'
        WHEN valuenum BETWEEN 6 AND 14 THEN 'borderline'
        ELSE 'myocardial injury'
      END AS hs_tnt_category
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE 
      itemid = 43121  
  ),

  index_hs_tnt AS (
    SELECT 
      subject_id,
      hadm_id,
      hs_tnt_category,
      ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY charttime) AS rn
    FROM 
      hs_tnt_categories
  ),

  patient_admissions AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
      p.anchor_age,
      p.gender,
      d.icd_code
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON 
      a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  )

SELECT 
  i.hs_tnt_category,
  COUNT(DISTINCT i.hadm_id) AS count,
  COUNT(DISTINCT i.hadm_id) * 100.0 / SUM(COUNT(DISTINCT i.hadm_id)) OVER () AS percentage,
  AVG(pa.los) AS mean_los
FROM 
  index_hs_tnt i
  JOIN patient_admissions pa 
  ON i.subject_id = pa.subject_id AND i.hadm_id = pa.hadm_id
WHERE 
  pa.gender = 'F'
  AND pa.anchor_age BETWEEN 81 AND 91
  AND (pa.icd_code LIKE '%I24%' OR pa.icd_code LIKE '%R07.2%')
  AND i.rn = 1
GROUP BY 
  i.hs_tnt_category
ORDER BY 
  i.hs_tnt_category;