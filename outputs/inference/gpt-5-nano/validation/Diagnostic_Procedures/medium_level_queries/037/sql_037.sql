WITH
-- 1) Define AMI-admitted admissions with primary/secondary AMI status and 1-7 day LOS
AMI_HADM AS (
  SELECT DISTINCT a.hadm_id,
         CASE 
           WHEN MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'Primary' 
           ELSE 'Secondary' 
         END AS ami_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND (
          (di.icd_version = 9 AND di.icd_code LIKE '410%')
       OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
        )
  GROUP BY a.hadm_id
),
AMI_HADM_STAY AS (
  SELECT h.hadm_id,
         h.ami_status,
         CASE
           WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
           WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
         END AS stay_group
  FROM AMI_HADM h
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON a.hadm_id = h.hadm_id
  WHERE TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
-- 2) Imaging counts per admission (aggregate across all ICU stays for the admission)
IMAGING_PER_ADM AS (
  SELECT hi.hadm_id,
         COUNT(*) AS imaging_counts
  FROM `physionet-data.mimiciv_3_1_icu.icustays` hi
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.hadm_id = hi.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN hi.intime AND hi.outtime
    AND (
          di.category IN ('Radiology','Imaging')
          OR di.label LIKE '%X-ray%' 
          OR di.label LIKE '%CT%' 
          OR di.label LIKE '%Radiograph%'
        )
  GROUP BY hi.hadm_id
),
IMAGING_ADM AS (
  SELECT hadm_id,
         SUM(imaging_counts) AS imaging_counts
  FROM IMAGING_PER_ADM
  GROUP BY hadm_id
)
-- 3) Aggregate per AMI group and LOS bin, computing median and IQR via approximate quantiles
SELECT s.ami_status AS ami_status,
       s.stay_group AS stay_group,
       APPROX_QUANTILES(COALESCE(i.imaging_counts, 0), 100)[OFFSET(50)] AS median_imaging,
       APPROX_QUANTILES(COALESCE(i.imaging_counts, 0), 100)[OFFSET(25)] AS q1_imaging,
       APPROX_QUANTILES(COALESCE(i.imaging_counts, 0), 100)[OFFSET(75)] AS q3_imaging
FROM AMI_HADM_STAY s
LEFT JOIN IMAGING_ADM i
  ON i.hadm_id = s.hadm_id
GROUP BY s.ami_status, s.stay_group
ORDER BY s.ami_status, s.stay_group;