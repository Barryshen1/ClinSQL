WITH cohort AS (
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 48 AND 58
),
hemorrhage AS (
  SELECT c.hadm_id,
         MAX(CASE
               WHEN di.long_title LIKE '%hemorrhagic%' OR di.long_title LIKE '%intracerebral%' OR di.long_title LIKE '%subarachnoid%'
               THEN 1 ELSE 0
             END) AS hemorrhagic_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON diag.subject_id = c.subject_id AND diag.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON diag.icd_code = di.icd_code AND diag.icd_version = di.icd_version
  GROUP BY c.hadm_id
),
meds48 AS (
  SELECT c.hadm_id,
         COUNT(DISTINCT LOWER(presc.drug)) AS total_meds_48h,
         SUM(CASE
               WHEN LOWER(presc.drug) LIKE '%sertraline%' OR LOWER(presc.drug) LIKE '%fluoxetine%' OR
                    LOWER(presc.drug) LIKE '%citalopram%' OR LOWER(presc.drug) LIKE '%escitalopram%' OR
                    LOWER(presc.drug) LIKE '%paroxetine%' OR LOWER(presc.drug) LIKE '%venlafaxine%' OR
                    LOWER(presc.drug) LIKE '%duloxetine%' OR LOWER(presc.drug) LIKE '%mirtazapine%' OR
                    LOWER(presc.drug) LIKE '%trazodone%' OR LOWER(presc.drug) LIKE '%sumatriptan%' OR
                    LOWER(presc.drug) LIKE '%rizatriptan%' OR LOWER(presc.drug) LIKE '%zolmitriptan%' OR LOWER(presc.drug) LIKE '%naratriptan%' OR
                    LOWER(presc.drug) LIKE '%phenelzine%' OR LOWER(presc.drug) LIKE '%tranylcypromine%' OR LOWER(presc.drug) LIKE '%isocarboxazid%' OR
                    LOWER(presc.drug) LIKE '%amitriptyline%' OR LOWER(presc.drug) LIKE '%nortriptyline%' OR LOWER(presc.drug) LIKE '%imipramine%'
             THEN 1 ELSE 0 END) AS serotonergic_48h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS presc
    ON presc.subject_id = c.subject_id AND presc.hadm_id = c.hadm_id
  WHERE presc.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id
),
data AS (
  SELECT c.hadm_id,
         CASE WHEN h.hemorrhagic_flag = 1 THEN 'Hemorrhagic' ELSE 'Control' END AS hemorrhagic_group,
         m.total_meds_48h,
         m.serotonergic_48h,
         TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
         CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality
  FROM cohort c
  LEFT JOIN hemorrhage h ON h.hadm_id = c.hadm_id
  LEFT JOIN meds48 m ON m.hadm_id = c.hadm_id
)
SELECT
  'Distribution' AS analysis,
  hemorrhagic_group,
  CASE
     WHEN serotonergic_48h >= 4 THEN '4+'
     WHEN serotonergic_48h = 3 THEN '3'
     WHEN serotonergic_48h = 2 THEN '2'
     WHEN serotonergic_48h = 1 THEN '1'
     ELSE '0'
  END AS serotonergic_48h_bucket,
  COUNT(*) AS n
FROM data
GROUP BY analysis, hemorrhagic_group, serotonergic_48h_bucket
ORDER BY hemorrhagic_group, serotonergic_48h_bucket;

-- 2) LOS and mortality by hemorrhagic status and serotonergic exposure
WITH cohort AS (
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 48 AND 58
),
hemorrhage AS (
  SELECT c.hadm_id,
         MAX(CASE
               WHEN di.long_title LIKE '%hemorrhagic%' OR di.long_title LIKE '%intracerebral%' OR di.long_title LIKE '%subarachnoid%'
               THEN 1 ELSE 0
             END) AS hemorrhagic_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON diag.subject_id = c.subject_id AND diag.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON diag.icd_code = di.icd_code AND diag.icd_version = di.icd_version
  GROUP BY c.hadm_id
),
meds48 AS (
  SELECT c.hadm_id,
         COUNT(DISTINCT LOWER(presc.drug)) AS total_meds_48h,
         SUM(CASE
               WHEN LOWER(presc.drug) LIKE '%sertraline%' OR LOWER(presc.drug) LIKE '%fluoxetine%' OR
                    LOWER(presc.drug) LIKE '%citalopram%' OR LOWER(presc.drug) LIKE '%escitalopram%' OR
                    LOWER(presc.drug) LIKE '%paroxetine%' OR LOWER(presc.drug) LIKE '%venlafaxine%' OR
                    LOWER(presc.drug) LIKE '%duloxetine%' OR LOWER(presc.drug) LIKE '%mirtazapine%' OR
                    LOWER(presc.drug) LIKE '%trazodone%' OR LOWER(presc.drug) LIKE '%sumatriptan%' OR
                    LOWER(presc.drug) LIKE '%rizatriptan%' OR LOWER(presc.drug) LIKE '%zolmitriptan%' OR LOWER(presc.drug) LIKE '%naratriptan%' OR
                    LOWER(presc.drug) LIKE '%phenelzine%' OR LOWER(presc.drug) LIKE '%tranylcypromine%' OR LOWER(presc.drug) LIKE '%isocarboxazid%' OR
                    LOWER(presc.drug) LIKE '%amitriptyline%' OR LOWER(presc.drug) LIKE '%nortriptyline%' OR LOWER(presc.drug) LIKE '%imipramine%'
             THEN 1 ELSE 0 END) AS serotonergic_48h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS presc
    ON presc.subject_id = c.subject_id AND presc.hadm_id = c.hadm_id
  WHERE presc.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.hadm_id
),
data AS (
  SELECT c.hadm_id,
         CASE WHEN h.hemorrhagic_flag = 1 THEN 'Hemorrhagic' ELSE 'Control' END AS hemorrhagic_group,
         m.total_meds_48h,
         m.serotonergic_48h,
         TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
         CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality,
         NTILE(4) OVER (ORDER BY m.total_meds_48h) AS quart4
  FROM cohort c
  LEFT JOIN hemorrhage h ON h.hadm_id = c.hadm_id
  LEFT JOIN meds48 m ON m.hadm_id = c.hadm_id
)
SELECT
  'TopQuartile' AS analysis,
  AVG(los_days) AS avg_los_days,
  AVG(CAST(mortality AS FLOAT64)) AS mortality_rate
FROM data
WHERE quart4 = 4;