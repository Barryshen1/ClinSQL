WITH
  icu_stays_with_demo AS (
    SELECT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.intime,
      i.outtime,
      p.gender,
      TIMESTAMP_DIFF(i.intime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) AS age,
      CASE WHEN d.icd_code IS NOT NULL THEN 1 ELSE 0 END AS has_heart_failure
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` p
      ON i.subject_id = p.subject_id
    LEFT JOIN (
      SELECT DISTINCT subject_id, hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 9 AND icd_code BETWEEN '402' AND '429') OR
        (icd_version = 10 AND icd_code BETWEEN 'I00' AND 'I52')
    ) d
      ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
    WHERE
      p.gender = 'M'
      AND TIMESTAMP_DIFF(i.intime, DATE(p.anchor_year - p.anchor_age, 1, 1), YEAR) BETWEEN 70 AND 80
  ),
  diagnostic_events AS (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      1 AS event_type
    FROM `physionet-data.mimiciv_3_1_icu.labevents` l
    INNER JOIN icu_stays_with_demo i
      ON l.subject_id = i.subject_id AND l.hadm_id = i.hadm_id AND l.stay_id = i.stay_id
    WHERE
      l.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)

    UNION ALL

    SELECT
      subject_id,
      hadm_id,
      stay_id,
      2 AS event_type
    FROM `physionet-data.mimiciv_3_1_icu.microbiologyevents` m
    INNER JOIN icu_stays_with_demo i
      ON m.subject_id = i.subject_id AND m.hadm_id = i.hadm_id AND m.stay_id = i.stay_id
    WHERE
      m.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)

    UNION ALL

    SELECT
      subject_id,
      hadm_id,
      NULL AS stay_id,
      3 AS event_type
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    INNER JOIN icu_stays_with_demo i
      ON h.subject_id = i.subject_id AND h.hadm_id = i.hadm_id
    WHERE
      h.chartdate BETWEEN DATE(i.intime) AND DATE(TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR))
      AND (
        h.hcpcs_cd BETWEEN '70000' AND '79999'
        OR h.hcpcs_cd BETWEEN '92000' AND '92999'
        OR h.hcpcs_cd BETWEEN '93000' AND '93999'
        OR h.hcpcs_cd BETWEEN '94000' AND '94999'
        OR h.hcpcs_cd BETWEEN '95000' AND '95999'
        OR h.hcpcs_cd BETWEEN '96000' AND '96999'
        OR h.hcpcs_cd BETWEEN '97000' AND '97999'
        OR h.hcpcs_cd BETWEEN '98000' AND '98999'
        OR h.hcpcs_cd BETWEEN '99000' AND '99999'
      )

    UNION ALL

    SELECT
      subject_id,
      hadm_id,
      NULL AS stay_id,
      4 AS event_type
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN icu_stays_with_demo i
      ON p.subject_id = i.subject_id AND p.hadm_id = i.hadm_id
    WHERE
      p.chartdate BETWEEN DATE(i.intime) AND DATE(TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR))
      AND (
        (p.icd_version = 9 AND p.icd_code BETWEEN '38.0' AND '38.9')
        OR (p.icd_version = 9 AND p.icd_code BETWEEN '88.0' AND '88.9')
        OR (p.icd_version = 9 AND p.icd_code BETWEEN '93.0' AND '93.9')
        OR (p.icd_version = 10 AND p.icd_code BETWEEN '39.00' AND '39.91')
        OR (p.icd_version = 10 AND p.icd_code BETWEEN '88.00' AND '88.99')
        OR (p.icd_version = 10 AND p.icd_code BETWEEN '93.00' AND '93.99')
      )
  ),
  patient_event_counts AS (
    SELECT
      i.subject_id,
      i.hadm_id,
      i.stay_id,
      i.has_heart_failure,
      COUNT(*) AS diagnostic_intensity
    FROM icu_stays_with_demo i
    LEFT JOIN diagnostic_events d
      ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id AND i.stay_id = d.stay_id
    GROUP BY i.subject_id, i.hadm_id, i.stay_id, i.has_heart_failure
  ),
  final_data AS (
    SELECT
      p.subject_id,
      p.hadm_id,
      p.diagnostic_intensity,
      p.has_heart_failure,
      TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS los_hours,
      a.hospital_expire_flag
    FROM patient_event_counts p
    INNER JOIN icu_stays_with_demo i
      ON p.subject_id = i.subject_id AND p.hadm_id = i.hadm_id AND p.stay_id = i.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON i.hadm_id = a.hadm_id
  )
SELECT
  'Heart Failure' AS group_name,
  AVG(diagnostic_intensity) AS mean_diagnostic_intensity,
  APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(50)] AS median_diagnostic_intensity,
  APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(75)] AS p75_diagnostic_intensity,
  APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(95)] AS p95_diagnostic_intensity,
  AVG(los_hours) AS mean_los_hours,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM final_data
WHERE has_heart_failure = 1

UNION ALL

SELECT
  'General ICU' AS group_name,
  AVG(diagnostic_intensity) AS mean_diagnostic_intensity,
  APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(50)] AS median_diagnostic_intensity,
  APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(75)] AS p75_diagnostic_intensity,
  APPROX_QUANTILES(diagnostic_intensity, 100)[OFFSET(95)] AS p95_diagnostic_intensity,
  AVG(los_hours) AS mean_los_hours,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM final_data
WHERE has_heart_failure = 0;