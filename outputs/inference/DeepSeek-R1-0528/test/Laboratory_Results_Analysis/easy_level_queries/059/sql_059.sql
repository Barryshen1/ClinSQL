WITH sepsis_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
    AND adm.subject_id = diag.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN (
        '038', '0380', '0381', '03810', '03811', '03812', '03819', '0382', '0383', 
        '0384', '03840', '03841', '03842', '03843', '03844', '03849', '0388', '0389', 
        '78552', '99591', '99592'
      ))
      OR
      (diag.icd_version = 10 AND diag.icd_code IN (
        'A40', 'A400', 'A401', 'A402', 'A403', 'A408', 'A409', 
        'A41', 'A410', 'A411', 'A412', 'A413', 'A414', 'A4150', 'A4151', 'A4152', 
        'A4159', 'A418', 'A419', 'R6520', 'R6521'
      ))
    )
),

platelet_events AS (
  SELECT
    sa.subject_id,
    sa.hadm_id,
    le.charttime,
    le.valuenum AS platelet_count
  FROM
    sepsis_admissions sa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sa.hadm_id = le.hadm_id
    AND sa.subject_id = le.subject_id
  WHERE
    le.itemid = 51265  -- Platelet Count
    AND DATE(le.charttime) = DATE(sa.dischtime)  -- Events on discharge day
),

last_platelet_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    platelet_count,
    ROW_NUMBER() OVER (
      PARTITION BY hadm_id
      ORDER BY charttime DESC
    ) AS rn
  FROM
    platelet_events
)

SELECT
  APPROX_QUANTILES(platelet_count, 100)[OFFSET(75)] AS percentile_75
FROM
  last_platelet_per_admission
WHERE
  rn = 1  -- Last platelet count per admission;