WITH patients_filtered AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE p.gender = 'F'
),
admissions_with_age AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 48 AND 58
),
stroke_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE icd_version = 10 
    AND (icd_code LIKE 'I61%' OR icd_code LIKE 'I62%')
),
stroke_patients AS (
  SELECT DISTINCT a.hadm_id
  FROM admissions_with_age a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN stroke_icd s
    ON di.icd_code = s.icd_code
),
control_patients AS (
  SELECT a.hadm_id
  FROM admissions_with_age a
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    WHERE di.hadm_id = a.hadm_id
      AND di.icd_code IN (SELECT icd_code FROM stroke_icd)
  )
),
cohort AS (
  SELECT hadm_id, 'stroke' AS cohort_group
  FROM stroke_patients
  UNION ALL
  SELECT hadm_id, 'control' AS cohort_group
  FROM control_patients
),
serotonergic_drugs AS (
  SELECT drug
  FROM UNNEST([
    'Citalopram', 'Escitalopram', 'Fluoxetine', 'Fluvoxamine', 'Paroxetine', 'Sertraline',
    'Venlafaxine', 'Duloxetine', 'Desvenlafaxine', 'Levomilnacipran', 'Milnacipran',
    'Amitriptyline', 'Clomipramine', 'Imipramine', 'Doxepin',
    'Trazodone', 'Nefazodone', 'Mirtazapine',
    'Sumatriptan', 'Rizatriptan', 'Zolmitriptan', 'Almotriptan', 'Eletriptan', 'Frovatriptan', 'Naratriptan',
    'Linezolid', 'Tramadol', 'Fentanyl', 'Meperidine', 'Dextromethorphan', 'Lithium', 'Tryptophan'
  ]) AS drug
),
drug_exposure AS (
  SELECT
    p.hadm_id,
    p.drug,
    p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN serotonergic_drugs s
    ON UPPER(p.drug) = UPPER(s.drug)
  WHERE p.starttime IS NOT NULL
),
first_48h_drugs AS (
  SELECT
    de.hadm_id,
    de.drug
  FROM drug_exposure de
  INNER JOIN admissions_with_age a
    ON de.hadm_id = a.hadm_id
  WHERE de.starttime >= a.admittime
    AND de.starttime <= DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
),
drug_count AS (
  SELECT
    hadm_id,
    COUNT(*) AS serotonergic_count
  FROM first_48h_drugs
  GROUP BY hadm_id
),
cohort_with_drugs AS (
  SELECT
    c.hadm_id,
    c.cohort_group,
    COALESCE(dc.serotonergic_count, 0) AS serotonergic_count
  FROM cohort c
  LEFT JOIN drug_count dc
    ON c.hadm_id = dc.hadm_id
),
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (PARTITION BY cohort_group ORDER BY serotonergic_count) AS complexity_quartile
  FROM cohort_with_drugs
)
SELECT
  q.hadm_id,
  q.cohort_group,
  q.serotonergic_count,
  q.complexity_quartile,
  DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
  a.hospital_expire_flag AS mortality
FROM quartiles q
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON q.hadm_id = a.hadm_id;