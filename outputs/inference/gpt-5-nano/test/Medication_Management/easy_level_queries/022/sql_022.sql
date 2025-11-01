WITH female_inpatients AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.dischtime IS NOT NULL
),
ccbprescriptions AS (
  SELECT fp.subject_id, fp.hadm_id, fp.starttime, fp.stoptime
  FROM female_inpatients fi
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS fp
    ON fi.subject_id = fp.subject_id AND fi.hadm_id = fp.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
    ON fp.subject_id = a2.subject_id AND fp.hadm_id = a2.hadm_id
  WHERE fp.starttime >= a2.admittime
    AND (a2.dischtime IS NOT NULL AND (fp.stoptime <= a2.dischtime OR fp.stoptime IS NULL))
    AND (
      LOWER(fp.drug) LIKE '%amlodipine%' OR
      LOWER(fp.drug) LIKE '%nifedipine%' OR
      LOWER(fp.drug) LIKE '%felodipine%' OR
      LOWER(fp.drug) LIKE '%nicardipine%' OR
      LOWER(fp.drug) LIKE '%nimodipine%' OR
      LOWER(fp.drug) LIKE '%isradipine%' OR
      LOWER(fp.drug) LIKE '%nisoldipine%'
    )
)
SELECT APPROX_MEDIAN(TIMESTAMP_DIFF(stoptime, starttime, SECOND) / 3600.0) AS median_duration_hours
FROM ccbprescriptions;