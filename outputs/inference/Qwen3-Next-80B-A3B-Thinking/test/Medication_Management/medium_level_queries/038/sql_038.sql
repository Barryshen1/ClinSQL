WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 57 AND 67
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = '9' AND d.icd_code LIKE '250%') OR
          (d.icd_version = '10' AND (
            d.icd_code LIKE 'E08%' OR
            d.icd_code LIKE 'E09%' OR
            d.icd_code LIKE 'E10%' OR
            d.icd_code LIKE 'E11%' OR
            d.icd_code LIKE 'E13%'
          ))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = '9' AND d.icd_code LIKE '428%') OR
          (d.icd_version = '10' AND d.icd_code LIKE 'I50%')
        )
    )
),
glp1_prescriptions AS (
  SELECT 
    subject_id,
    hadm_id,
    starttime,
    drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    drug LIKE '%liraglutide%' OR
    drug LIKE '%semaglutide%' OR
    drug LIKE '%exenatide%' OR
    drug LIKE '%dulaglutide%' OR
    drug LIKE '%albiglutide%' OR
    drug LIKE '%lixisenatide%'
),
cohort_with_glp1 AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    MIN(g.starttime) AS first_glp1_time,
    MAX(CASE WHEN g.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '72' HOUR THEN 1 ELSE 0 END) AS has_first_72,
    MAX(CASE WHEN g.starttime BETWEEN c.dischtime - INTERVAL '24' HOUR AND c.dischtime THEN 1 ELSE 0 END) AS has_final_24,
    CASE 
      WHEN MIN(g.starttime) IS NOT NULL AND MIN(g.starttime) BETWEEN c.admittime AND c.admittime + INTERVAL '72' HOUR THEN 1 
      ELSE 0 
    END AS init_first_72,
    CASE 
      WHEN MIN(g.starttime) IS NOT NULL AND MIN(g.starttime) BETWEEN c.dischtime - INTERVAL '24' HOUR AND c.dischtime THEN 1 
      ELSE 0 
    END AS init_final_24
  FROM cohort c
  LEFT JOIN glp1_prescriptions g ON c.subject_id = g.subject_id AND c.hadm_id = g.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
)
SELECT 
  AVG(has_first_72) * 100 AS prevalence_first_72,
  AVG(has_final_24) * 100 AS prevalence_final_24,
  (AVG(has_final_24) - AVG(has_first_72)) * 100 AS abs_change_prevalence,
  (AVG(has_final_24) - AVG(has_first_72)) / NULLIF(AVG(has_first_72), 0) * 100 AS rel_change_prevalence,
  AVG(init_first_72) * 100 AS init_rate_first_72,
  AVG(init_final_24) * 100 AS init_rate_final_24,
  (AVG(init_final_24) - AVG(init_first_72)) * 100 AS abs_change_init,
  (AVG(init_final_24) - AVG(init_first_72)) / NULLIF(AVG(init_first_72), 0) * 100 AS rel_change_init
FROM cohort_with_glp1;