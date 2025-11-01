WITH ugib_copd AS (
  SELECT
    di.hadm_id,
    MAX(CASE
          WHEN REGEXP_CONTAINS(LOWER(dd.long_title), r'upper.*gastro.*bleed|upper.*gastrointestinal.*bleed|gastro.*bleed|bleed')
            THEN 1
          ELSE 0
        END) AS has_ugib,
    MAX(CASE
          WHEN REGEXP_CONTAINS(LOWER(dd.long_title), r'(copd|chronic obstructive pulmonary disease)') 
               AND REGEXP_CONTAINS(LOWER(dd.long_title), r'exacerbation')
            THEN 1
          ELSE 0
        END) AS has_copd_exac
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
),
eligible_admissions AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN ugib_copd AS g
    ON a.hadm_id = g.hadm_id
  WHERE p.gender = 'Female'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 69 AND 79
    AND g.has_ugib = 1
    AND g.has_copd_exac = 1
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(49)] AS median_los_days
FROM eligible_admissions;