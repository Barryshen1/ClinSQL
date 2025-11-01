WITH male_stroke_admissions AS (
  SELECT 
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (
      (d.icd_version = 9 AND d.icd_code IN (
        '43401', '43411', '43491', 
        '43301', '43311', '43321', '43331', '43381', '43391'
      ))
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
  GROUP BY d.hadm_id
),
admissions_with_discharge AS (
  SELECT 
    adm.hadm_id,
    DATE(adm.dischtime) AS disch_date
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN male_stroke_admissions msa
    ON adm.hadm_id = msa.hadm_id
  WHERE adm.dischtime IS NOT NULL
),
glucose_on_discharge AS (
  SELECT 
    a.hadm_id,
    lab.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY a.hadm_id 
      ORDER BY lab.charttime DESC
    ) AS rn
  FROM admissions_with_discharge a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON a.hadm_id = lab.hadm_id
  WHERE lab.itemid = 50931
    AND DATE(lab.charttime) = a.disch_date
)
SELECT 
  APPROX_QUANTILES(valuenum, 1000)[OFFSET(750)] 
  - APPROX_QUANTILES(valuenum, 1000)[OFFSET(250)] AS iqr
FROM glucose_on_discharge
WHERE rn = 1 AND valuenum IS NOT NULL;