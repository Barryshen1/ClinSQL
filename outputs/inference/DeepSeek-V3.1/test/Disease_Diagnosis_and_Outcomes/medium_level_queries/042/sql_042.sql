WITH ami_patients AS (
    SELECT DISTINCT
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        adm.discharge_location,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        CASE 
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) >= 8 THEN '>=8'
            ELSE 'Other'
        END AS los_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 69 AND 79
        AND d.long_title LIKE 'Acute myocardial infarction%'
    -- Exclude shock (R57.x)
    AND adm.hadm_id NOT IN (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE icd_code LIKE 'R57%'
    )
    -- Exclude respiratory failure (J96.0, J96.2, J96.9)
    AND adm.hadm_id NOT IN (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE icd_code IN ('J960', 'J962', 'J969')
    )
),

median_los AS (
  SELECT
    los_group,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los
  FROM ami_patients
  GROUP BY los_group
)

SELECT 
    a.los_group,
    COUNT(*) AS num_patients,
    ROUND(AVG(a.hospital_expire_flag) * 100, 2) AS mortality_percent,
    m.median_los,
    a.discharge_location,
    COUNT(a.discharge_location) AS count_destination
FROM ami_patients a
LEFT JOIN median_los m
  ON a.los_group = m.los_group
GROUP BY a.los_group, a.discharge_location, m.median_los
ORDER BY a.los_group, count_destination DESC;