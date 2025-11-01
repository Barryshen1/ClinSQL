WITH pneumonia_dx AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE ( (icd_version = 9 AND (
              icd_code BETWEEN '480' AND '486' OR icd_code = '4870'))
       OR (icd_version = 10 AND (
              icd_code LIKE 'J12%' OR icd_code LIKE 'J13%' OR icd_code LIKE 'J14%' OR
              icd_code LIKE 'J15%' OR icd_code LIKE 'J16%' OR icd_code LIKE 'J17%' OR
              icd_code LIKE 'J18%'))
        )
),
charlson_flags AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    MAX(CASE WHEN ( (icd_version=9 AND icd_code BETWEEN '4280' AND '4289')
                 OR (icd_version=10 AND icd_code LIKE 'I50%') )
         THEN 1 ELSE 0 END) AS CHF,
    MAX(CASE WHEN ( (icd_version=9 AND icd_code BETWEEN '5850' AND '5856')
                 OR (icd_version=10 AND icd_code LIKE 'N18%') )
         THEN 2 ELSE 0 END) AS Renal,
    MAX(CASE WHEN ( (icd_version=9 AND (icd_code BETWEEN '2500' AND '2509'))
                 OR (icd_version=10 AND icd_code LIKE 'E10%' OR icd_code LIKE 'E11%') )
         THEN 1 ELSE 0 END) AS Diabetes,
    MAX(CASE WHEN ( (icd_version=9 AND icd_code BETWEEN '4100' AND '4109')
                 OR (icd_version=10 AND icd_code LIKE 'I21%') )
         THEN 1 ELSE 0 END) AS MI
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.subject_id, di.hadm_id
),
charlson_scores AS (
  SELECT
    subject_id,
    hadm_id,
    CHF + Renal + Diabetes + MI AS cci
  FROM charlson_flags
),
cci_quartiles AS (
  SELECT
    APPROX_QUANTILES(cci, 4)[OFFSET(3)] AS q3
  FROM charlson_scores
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_adm,
    p.gender,
    a.admittime,
    COALESCE(p.dod, a.dischtime) AS endtime,
    cs.cci
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN pneumonia_dx pdx
    ON a.hadm_id = pdx.hadm_id
  JOIN charlson_scores cs
    ON a.hadm_id = cs.hadm_id
  CROSS JOIN cci_quartiles qt
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 73 AND 83
    AND cs.cci >= qt.q3
),
complications AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE ( (icd_version=9 AND (
            icd_code BETWEEN '5845' AND '5849'
         OR icd_code BETWEEN '99591' AND '99592'
         OR icd_code BETWEEN '4100' AND '4109'
         OR icd_code BETWEEN '434' AND '436'
         ))
       OR (icd_version=10 AND (
            icd_code LIKE 'N17%'
         OR icd_code LIKE 'A41%'
         OR icd_code LIKE 'I21%'
         OR icd_code LIKE 'I63%' OR icd_code LIKE 'I64%'
         ))
        )
),
cohort_with_flags AS (
  SELECT
    c.*,
    CASE WHEN comp.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS major_complication,
    DATE_DIFF(c.endtime, c.admittime, DAY) AS survival_days
  FROM cohort c
  LEFT JOIN complications comp
    ON c.hadm_id = comp.hadm_id
),
summary AS (
  SELECT
    100 * AVG(hospital_expire_flag) AS mortality_pct,
    100 * AVG(major_complication) AS complication_pct,
    APPROX_QUANTILES(survival_days, 2)[OFFSET(1)] AS median_survival_days
  FROM cohort_with_flags
),
risk_percentiles AS (
  SELECT
    subject_id,
    hadm_id,
    PERCENT_RANK() OVER (ORDER BY hospital_expire_flag DESC, major_complication DESC, cci DESC) AS risk_percentile
  FROM cohort_with_flags
)
SELECT
  s.mortality_pct,
  s.complication_pct,
  s.median_survival_days,
  rp.subject_id,
  rp.hadm_id,
  rp.risk_percentile
FROM summary s
CROSS JOIN risk_percentiles rp
ORDER BY rp.risk_percentile DESC;