WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year BETWEEN 45 AND 55
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE 
        (d.icd_version = 9 AND di.icd_code LIKE '250%' AND (di.icd_code LIKE '%0' OR di.icd_code LIKE '%2'))
        OR (d.icd_version = 10 AND di.icd_code LIKE 'E11%')
    )
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE 
        (d.icd_version = 9 AND di.icd_code LIKE '428%')
        OR (d.icd_version = 10 AND di.icd_code LIKE 'I50%')
    )
),
glp1_events AS (
  SELECT 
    c.hadm_id,
    e.charttime
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
  WHERE 
    LOWER(e.medication) LIKE '%exenatide%'
    OR LOWER(e.medication) LIKE '%liraglutide%'
    OR LOWER(e.medication) LIKE '%dulaglutide%'
    OR LOWER(e.medication) LIKE '%semaglutide%'
    OR LOWER(e.medication) LIKE '%lixisenatide%'
    OR LOWER(e.medication) LIKE '%albiglutide%'
    OR LOWER(e.medication) LIKE '%byetta%'
    OR LOWER(e.medication) LIKE '%bydureon%'
    OR LOWER(e.medication) LIKE '%victoza%'
    OR LOWER(e.medication) LIKE '%saxenda%'
    OR LOWER(e.medication) LIKE '%trulicity%'
    OR LOWER(e.medication) LIKE '%ozempic%'
    OR LOWER(e.medication) LIKE '%rybelsus%'
    OR LOWER(e.medication) LIKE '%wegovy%'
    OR LOWER(e.medication) LIKE '%adlyxin%'
    OR LOWER(e.medication) LIKE '%tanzeum%'
)
SELECT
  COUNT(DISTINCT c.hadm_id) AS total_admissions,
  COUNT(DISTINCT 
    CASE WHEN ge.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) 
    THEN c.hadm_id END
  ) AS started_within_72h,
  COUNT(DISTINCT 
    CASE WHEN ge.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime 
    THEN c.hadm_id END
  ) AS on_in_last_48h,
  ROUND(
    COUNT(DISTINCT 
      CASE WHEN ge.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) 
      THEN c.hadm_id END
    ) * 100.0 / COUNT(DISTINCT c.hadm_id), 2
  ) AS pct_started_within_72h,
  ROUND(
    COUNT(DISTINCT 
      CASE WHEN ge.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime 
      THEN c.hadm_id END
    ) * 100.0 / COUNT(DISTINCT c.hadm_id), 2
  ) AS pct_on_in_last_48h,
  ROUND(
    (COUNT(DISTINCT 
        CASE WHEN ge.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime 
        THEN c.hadm_id END) 
     - COUNT(DISTINCT 
        CASE WHEN ge.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) 
        THEN c.hadm_id END)
    ) * 100.0 / COUNT(DISTINCT c.hadm_id), 2
  ) AS net_change
FROM cohort c
LEFT JOIN glp1_events ge
  ON c.hadm_id = ge.hadm_id;