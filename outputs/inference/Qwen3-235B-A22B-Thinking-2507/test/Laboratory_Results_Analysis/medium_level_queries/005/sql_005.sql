WITH eligible_admissions AS (
  SELECT
    a.hadm_id,
    COALESCE(a.edregtime, a.admittime) AS start_time,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Filter males aged 35-45 at admission
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 35 AND 45
    -- Primary diagnosis: chest pain (R07%/786.5) or AMI (I21%/410%)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND (
          (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'R07%'))
          OR (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '786.5'))
        )
    )
),
first_troponin AS (
  SELECT
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id 
      ORDER BY l.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN eligible_admissions e
    ON l.hadm_id = e.hadm_id
  WHERE l.itemid = 50189  -- High-sensitivity troponin T
    AND l.valuenum IS NOT NULL
    AND l.valueuom = 'ng/L'
    AND l.charttime >= e.start_time
    AND l.charttime <= e.dischtime
)
SELECT
  CASE
    WHEN valuenum < 14 THEN 'normal'
    WHEN valuenum < 60 THEN 'borderline'  -- 14 <= valuenum < 60
    ELSE 'myocardial_injury'
  END AS category,
  COUNT(*) AS count
FROM first_troponin
WHERE rn = 1  -- First measurement per admission
GROUP BY category;