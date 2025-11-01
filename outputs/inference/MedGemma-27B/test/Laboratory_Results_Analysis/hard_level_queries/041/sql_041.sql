SELECT
    pt.subject_id,
    pt.hadm_id,
    COUNT(le.labevent_id) AS critical_lab_count
  FROM PatientThreshold AS pt
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON pt.subject_id = le.subject_id AND pt.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN pt.admittime AND TIMESTAMP_ADD(pt.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.valueuom IS NOT NULL
    AND le.flag IS NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY
    pt.subject_id,
    pt.hadm_id
);